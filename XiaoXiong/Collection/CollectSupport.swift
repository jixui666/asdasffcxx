import Combine
import Darwin
import Foundation

// MARK: - 移植自 3105（ThreeOneOSFive/helpers/Utils.swift）
//
// 采集链路共用的基础设施：
//   * AppLog / log(...)      —— 进程内日志 + 加密落盘（Documents/Logs/log）
//   * AppInfo                —— 系统版本 / 机型
//   * AppUpdateChecker       —— 上报用的 app_version
//   * CollectSandboxState    —— 沙箱授权状态（替代 3105 的 KernelExploit 判定）
//   * PatchPathValidator     —— bundle id 规范化校验（3105 由 PatchProjectModels 提供）
//
// 3105 的 original 语义保持不变：落盘日志逐行 AES-128-CBC 加密后 Base64 存储，
// 且过滤中文与 /api、protocol: 行。

class AppLog: ObservableObject {
    static let shared = AppLog()
    @Published var entries: [String] = []

    private static let writeQueue = DispatchQueue(label: "com.uuvpn.collect.log-persist")
    private static let maximumLogFileBytes: UInt64 = 1_048_576
    private static let maximumRotatedLogFiles = 3
    private static var fileHandle: FileHandle?

    private static let lineTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let fileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    static var persistentLogPath: String {
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return "" }
        return documentsURL
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("log", isDirectory: false)
            .path
    }

    func append(_ msg: String) {
        DispatchQueue.main.async { self.entries.append(msg) }
        Self.persist(msg)
    }

    func flush() {
        Self.writeQueue.async {
            if let handle = Self.fileHandle {
                try? handle.synchronize()
            }
        }
    }

    private static func persist(_ message: String) {
        guard shouldPersistToFile(message) else { return }
        writeQueue.async {
            guard let logURL = ensureLogFile() else {
                try? fileHandle?.close()
                fileHandle = nil
                return
            }
            if let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
               let size = (attributes[.size] as? NSNumber)?.uint64Value,
               size >= maximumLogFileBytes {
                rotateLogFile(at: logURL)
            }
            guard let handle = fileHandle else { return }
            do {
                try handle.seekToEnd()
                let line = lineTimestampFormatter.string(from: Date()) + " " + message + "\n"
                if let plain = line.data(using: .utf8),
                   let ciphertext = ProtocolCrypto.encrypt(plain),
                   let encoded = (ciphertext.base64EncodedString() + "\n").data(using: .utf8) {
                    try handle.write(contentsOf: encoded)
                }
            } catch {
                try? handle.close()
                fileHandle = nil
            }
        }
    }

    /// 落盘日志保持干净：不写中文，也不写 protocol / API 请求行。
    private static func shouldPersistToFile(_ message: String) -> Bool {
        if message.contains("/api") || message.contains("protocol:") {
            return false
        }
        for scalar in message.unicodeScalars {
            let value = scalar.value
            if (0x3000...0x303F).contains(value)
                || (0x3400...0x4DBF).contains(value)
                || (0x4E00...0x9FFF).contains(value)
                || (0xFF00...0xFFEF).contains(value) {
                return false
            }
        }
        return true
    }

    private static func ensureLogFile() -> URL? {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let logsDirectory = documentsURL.appendingPathComponent("Logs", isDirectory: true)
        do {
            try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let logURL = logsDirectory.appendingPathComponent("log", isDirectory: false)
        if !fileManager.fileExists(atPath: logURL.path) {
            guard fileManager.createFile(atPath: logURL.path, contents: nil) else { return nil }
        }
        if fileHandle == nil {
            fileHandle = try? FileHandle(forUpdating: logURL)
        }
        guard fileHandle != nil else { return nil }
        return logURL
    }

    private static func rotateLogFile(at currentURL: URL) {
        try? fileHandle?.close()
        fileHandle = nil
        let fileManager = FileManager.default
        let directory = currentURL.deletingLastPathComponent()
        var rotatedURL = directory.appendingPathComponent(
            "log-\(fileTimestampFormatter.string(from: Date()))",
            isDirectory: false
        )
        var suffix = 2
        while fileManager.fileExists(atPath: rotatedURL.path) {
            rotatedURL = directory.appendingPathComponent(
                "log-\(fileTimestampFormatter.string(from: Date()))-\(suffix)",
                isDirectory: false
            )
            suffix += 1
        }
        try? fileManager.moveItem(at: currentURL, to: rotatedURL)
        pruneRotatedLogFiles(in: directory)
        _ = ensureLogFile()
    }

    private static func pruneRotatedLogFiles(in directory: URL) {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasPrefix("log-") }
            .sorted(by: >)
        for name in names.dropFirst(maximumRotatedLogFiles) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}

func log(_ msg: String) { AppLog.shared.append("[UUV] \(msg)") }

// Retain the pipe for the app's lifetime so stdout/stderr stay redirected.
private var collectLogCapturePipe: Pipe?

/// Redirect stdout/stderr (C printf / NSLog) into the in-app log view.
/// 与 3105 的实现一致，由 CollectBootstrap 按需开启。
func setupLogCapture() {
    guard collectLogCapturePipe == nil else { return }
    let pipe = Pipe()
    collectLogCapturePipe = pipe

    setvbuf(stdout, nil, _IONBF, 0)
    setvbuf(stderr, nil, _IONBF, 0)
    let writeFd = pipe.fileHandleForWriting.fileDescriptor
    if dup2(writeFd, STDOUT_FILENO) < 0 || dup2(writeFd, STDERR_FILENO) < 0 {
        log("setupLogCapture: dup2 failed, log capture disabled")
        collectLogCapturePipe = nil
        return
    }

    pipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        guard !data.isEmpty else { return }
        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                DispatchQueue.main.async {
                    AppLog.shared.append(trimmed)
                }
            }
        }
    }
}

enum AppInfo {
    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static var versionTuple: (major: Int, minor: Int, patch: Int) {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return (v.majorVersion, v.minorVersion, v.patchVersion)
    }

    static var osBuild: String {
        var size: size_t = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else {
            return "Unknown"
        }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &value, &size, nil, 0) == 0 else {
            return "Unknown"
        }
        return String(cString: value)
    }

    static var machineName: String {
        var s = utsname()
        uname(&s)
        return Mirror(reflecting: s.machine).children.reduce("") { id, e in
            guard let v = e.value as? Int8, v != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(v)))
        }
    }

    static var displayMachineName: String {
#if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machineName
#else
        return machineName
#endif
    }
}

enum AppUpdateChecker {
    /// 上报字段 app_version：与 3105 一样优先取
    /// AppReleaseDisplayVersion，其次 CFBundleShortVersionString。
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "AppReleaseDisplayVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0"
    }
}

// MARK: - 沙箱授权状态

/// 3105 用 KernelExploit.requiresSandboxEscape / hasSandboxAccess 判断
/// “提权是否生效”。采集链路只关心“容器能否被授权打开”，所以这里直接用
/// bad_query 对 App 数据容器根做一次试探授权：拿到 handle 即视为可用。
enum CollectSandboxState {
    /// iOS >= 26 需要完整沙箱逃逸才能读别人的容器（与 3105 判定一致）。
    static let requiresSandboxEscape: Bool =
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26

    private static let probePath = "/var/mobile/Containers/Data/Application"

    private static var cached: Bool?

    static var hasSandboxAccess: Bool {
        if let cached { return cached }
        var probe = probePath.utf8CString.map { Int8($0) }
        let handle = bad_query(&probe, true, nil, false)
        let available = handle >= 0
        if available { bad_query_release(handle) }
        cached = available
        return available
    }

    static func invalidate() {
        cached = nil
    }
}

// MARK: - 包限制常量（3105 由 PatchProjectModels 提供，这里只保留用到的项）

enum PatchPackageLimits {
    static let maximumPathBytes = 4_096
}

// MARK: - bundle identifier 校验（3105 由 PatchProjectModels 提供）

enum PatchIdentifierError: Error {
    case invalidBundleIdentifier
}

enum PatchPathValidator {
    static func canonicalBundleIdentifier(_ rawValue: String) throws -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.utf8.count <= 255,
              UUID(uuidString: value) == nil,
              !value.contains("/"),
              !value.contains("\\"),
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw PatchIdentifierError.invalidBundleIdentifier
        }

        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2 else {
            throw PatchIdentifierError.invalidBundleIdentifier
        }

        for component in components {
            guard !component.isEmpty,
                  component.unicodeScalars.allSatisfy({ scalar in
                      let value = scalar.value
                      return (48...57).contains(value)
                          || (65...90).contains(value)
                          || (97...122).contains(value)
                          || value == 45
                  }),
                  component.first != "-",
                  component.last != "-"
            else {
                throw PatchIdentifierError.invalidBundleIdentifier
            }
        }
        return value
    }
}
