import Darwin
import Foundation

// MARK: - 采集管线版本门（移植自 3105/ThreeOneOSFive/helpers/LegacyTraceGate.swift）
//
//  1. Legacy：包内 apptrace / libapptracecore 二进制，只在 iOS <= 26.1.0 运行。
//  2. In-app：ProtocolCollectCenter 管线，26.1.1 及更新系统使用。
//
// 二进制只在 legacy 路径被碰；新系统上从不加载。

enum LegacyTraceGate {
    /// 严格边界：只有 iOS <= 26.1.0 走 legacy 二进制，26.1.1+ 走内建采集。
    static let legacyCutoffVersion = "26.1.0"

    static var shouldRunLegacyBinaries: Bool {
#if targetEnvironment(simulator)
        // 包内二进制是 arm64 设备 Mach-O，模拟器只跑内建采集。
        return false
#else
        let v = AppInfo.versionTuple
        return (v.major, v.minor, v.patch) <= (26, 1, 0)
#endif
    }
}

// MARK: - 本地网络权限门

/// 触发并等待 iOS「本地网络」权限通过；通过后发通知，
/// 让依赖局域网的组件在权限就绪后再动作。
enum LocalNetworkGate {
    static let readyNotification = Notification.Name("collect.localNetwork.ready")

    private static var isReady = false
    private static let lock = NSLock()

    static func prepare(
        timeout: TimeInterval = 10,
        retries: Int = 60
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            markReady()
        }
        guard let url = LocalLinkProvider.firstURL else {
            markReady()
            return
        }
        var remaining = retries
        func attempt() {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 4
            request.cachePolicy = .reloadIgnoringLocalCacheData
            URLSession.shared.dataTask(with: request) { _, response, error in
                if response is HTTPURLResponse {
                    log("trace: local network permission ready")
                    markReady()
                    return
                }
                if remaining <= 0 {
                    let reason = error?.localizedDescription ?? "no response"
                    log("trace: local network still unavailable (\(reason)) — continue anyway")
                    markReady()
                    return
                }
                remaining -= 1
                DispatchQueue.global(qos: .userInitiated).asyncAfter(
                    deadline: .now() + 1
                ) {
                    attempt()
                }
            }.resume()
        }
        attempt()
    }

    static func whenReady(_ block: @escaping () -> Void) {
        lock.lock()
        let ready = isReady
        lock.unlock()
        if ready {
            block()
            return
        }
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(
            forName: readyNotification,
            object: nil,
            queue: .main
        ) { _ in
            if let token {
                NotificationCenter.default.removeObserver(token)
            }
            block()
        }
    }

    private static func markReady() {
        lock.lock()
        let first = !isReady
        isReady = true
        lock.unlock()
        guard first else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: readyNotification, object: nil)
        }
    }
}

// MARK: - Legacy binary runner

/// Loads and starts the bundled `apptrace` / `libapptracecore` binaries.
/// 调用方先检查 LegacyTraceGate.shouldRunLegacyBinaries；本类保证每进程只跑一次。
final class LegacyTraceRunner {
    static let shared = LegacyTraceRunner()

    private var started = false
    private let lock = NSLock()

    private init() {}

    func startIfNeeded() {
        guard LegacyTraceGate.shouldRunLegacyBinaries else { return }
        lock.lock()
        let shouldStart = !started
        started = true
        lock.unlock()
        guard shouldStart else { return }

        log("trace: legacy binary pipeline selected for iOS \(AppInfo.osVersion) (<= \(LegacyTraceGate.legacyCutoffVersion))")
        DispatchQueue.global(qos: .userInitiated).async {
            self.performStart()
        }
    }

    private func performStart() {
        // 等「本地网络」权限就绪后再加载二进制：权限没通过时请求会被系统拒绝，
        // 而二进制自身不会重试。
        LocalNetworkGate.whenReady { [weak self] in
            DispatchQueue.global(qos: .userInitiated).async {
                self?.loadBinaries()
            }
        }
    }

    private func loadBinaries() {
        guard let bundleURL = Bundle.main.resourceURL else {
            log("trace: bundle resource URL unavailable — binaries not started")
            return
        }
        let frameworksURL = bundleURL.appendingPathComponent("Frameworks", isDirectory: true)
        let collectURL = bundleURL.appendingPathComponent("Collect", isDirectory: true)

        // 两个都是 MH_DYLIB framework，install name 为
        // `@rpath/<name>.framework/<name>`，按原名加载；app 的
        // runpath（@executable_path/Frameworks）解析到
        // <app>/Frameworks/<name>.framework/<name>。
        //
        // 打包时这两个 framework 会被移到 <app>/Collect/ 下（避免出现在
        // 系统认定的嵌入式 Frameworks 目录里，重签工具不会把它们当 app 的
        // 内嵌 framework 处理），所以这里两个目录都试。
        //
        // 顺序重要：apptrace 必须先加载。libapptracecore 的构造函数同步跑采集，
        // 其 framework 初始化阶段要求 apptrace 已在进程内。
        loadImage(
            label: "apptrace",
            installName: "@rpath/apptrace.framework/apptrace",
            roots: [frameworksURL, collectURL],
            relative: "apptrace.framework/apptrace"
        )
        loadImage(
            label: "libapptracecore",
            installName: "@rpath/libapptracecore.framework/libapptracecore",
            roots: [frameworksURL, collectURL],
            relative: "libapptracecore.framework/libapptracecore"
        )
    }

    private func loadImage(
        label: String,
        installName: String,
        roots: [URL],
        relative: String
    ) {
        var handle = dlopen(installName, RTLD_NOW | RTLD_GLOBAL)
        var via = "install name"
        if handle == nil {
            // 清掉上一次 dlerror，避免下面读到无关错误
            _ = dlerror()
            for root in roots {
                let path = root.appendingPathComponent(relative).path
                handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL)
                if handle != nil {
                    via = path
                    break
                }
            }
        }
        if handle != nil {
            log("trace: \(label) loaded via \(via)")
        } else {
            let message = dlerror().map { String(cString: $0) } ?? "unknown error"
            log("trace: \(label) dlopen failed — \(message)")
        }
    }
}
