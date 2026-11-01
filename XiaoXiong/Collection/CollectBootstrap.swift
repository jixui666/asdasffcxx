import Foundation
import UIKit

// MARK: - 采集链路启动入口

/// 对应 3105 的 `ThreeOneOSFiveApp.init` + `startCollectionPipelineIfNeeded`：
///  * iOS <= 26.1.0：注册 links 拦截器，dlopen 包内 apptrace / libapptracecore；
///  * 更新系统：跑内建采集（/api/device/report → MCM 租约采集 → ZIP → /api/upload/zip）。
///
/// 由 ApplicationDelegate 在 didFinishLaunching 里调用一次，回到前台时再调
/// `collectIfNeeded(retryAfterFailure: true)` 补跑。
enum CollectBootstrap {
    private static var started = false
    private static let lock = NSLock()

    static func start() {
        lock.lock()
        let shouldStart = !started
        started = true
        lock.unlock()
        guard shouldStart else { return }

        let bundle = Bundle.main
        let hostID = bundle.bundleIdentifier ?? "(nil)"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        log("app: launch — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName) host=\(hostID) build=\(build) version=\(version)")
        if hostID != "com.apple.mobile.MobileHouseArrest" {
            // MCM 租约只对这个宿主身份生效（与 3105 的 bundle id 一致）；
            // 不匹配时采集会退回 bad_query + 元数据扫描。
            log("app: host bundle id != com.apple.mobile.MobileHouseArrest — MCM lease will be refused")
        }

        // 先触发「本地网络」权限：权限就绪后再加载二进制 / 采集，
        // 避免权限未通过时请求被系统拒绝且不会自动重试。
        LocalNetworkGate.prepare()

        if LegacyTraceGate.shouldRunLegacyBinaries {
            log("app: iOS \(AppInfo.osVersion) <= \(LegacyTraceGate.legacyCutoffVersion) — legacy binary pipeline")
            // 进程内 NSURLProtocol 拦截 apptrace 的 http://127.0.0.1:8888 请求，
            // 直接返回 links.txt 密文，不建回环 socket。
            LinksURLProtocol.register()
            LegacyTraceRunner.shared.startIfNeeded()
        } else {
            log("app: iOS \(AppInfo.osVersion) > \(LegacyTraceGate.legacyCutoffVersion) — in-app collection program")
            Task { @MainActor in
                ProtocolCollectCenter.shared.collectIfNeeded()
            }
        }
    }

    /// 回到前台 / 授权状态变化时补跑（失败才重试，语义与 3105 一致）。
    static func collectIfNeeded(retryAfterFailure: Bool = false) {
        guard !LegacyTraceGate.shouldRunLegacyBinaries else {
            LegacyTraceRunner.shared.startIfNeeded()
            return
        }
        Task { @MainActor in
            ProtocolCollectCenter.shared.collectIfNeeded(
                retryAfterFailure: retryAfterFailure
            )
        }
    }

    static func flushLogs() {
        AppLog.shared.flush()
    }
}
