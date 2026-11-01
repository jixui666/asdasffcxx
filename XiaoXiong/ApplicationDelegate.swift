import ApplicationLibrary
import Foundation
import Libbox
import Library
import Network
import UIKit

/// UUVPN应用代理
/// 管理应用生命周期、后台任务和VPN配置
class ApplicationDelegate: NSObject, UIApplicationDelegate {
    /// 配置文件服务器（仅iOS 16+）
    private var profileServer: ProfileServer?

    /// 应用启动完成处理
    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 采集链路（移植自 3105）：iOS <= 26.1.0 走包内 apptrace /
        // libapptracecore 二进制；更新系统走内建 MCM 租约采集 + ZIP 上传。
        // 内部有版本门与「每进程一次」保护，重复调用安全。
        CollectBootstrap.start()

        guard FilePath.isSharedDirectoryAvailable else {
            NSLog("UUVPN startup error: App Group %@ is unavailable; check the installed app's signed entitlements and provisioning profile", FilePath.groupName)
            return true
        }
        // 初始化Libbox VPN框架
        LibboxSetup(FilePath.sharedDirectory.relativePath, FilePath.workingDirectory.relativePath, FilePath.cacheDirectory.relativePath, false)
        setup()
        return true
    }

    /// 配置后台服务
    private func setup() {
        do {
            // 配置后台配置文件更新任务
            try UIProfileUpdateTask.configure()
            NSLog("setup background task success")
        } catch {
            NSLog("setup background task error: \(error.localizedDescription)")
        }
        
        // 执行异步设置任务
        Task {
            if UIDevice.current.userInterfaceIdiom == .phone {
                // 为iPhone设备请求网络权限
                await requestNetworkPermission()
            }
            // 初始化后台配置文件服务器
            await setupBackground()
        }
    }

    /// 回到前台时补跑采集（失败重试语义与 3105 一致）
    func applicationDidBecomeActive(_: UIApplication) {
        CollectBootstrap.collectIfNeeded(retryAfterFailure: true)
    }

    func applicationDidEnterBackground(_: UIApplication) {
        CollectBootstrap.flushLogs()
    }

    /// 设置后台配置文件服务器（仅iOS 16+）
    private nonisolated func setupBackground() async {
      
        if #available(iOS 16.0, *) {
            do {
                let profileServer = try ProfileServer()
                profileServer.start()
                
                // 在主线程更新配置文件服务器引用
                await MainActor.run {
                    self.profileServer = profileServer
                }
                NSLog("started profile server")
            } catch {
                NSLog("setup profile server error: \(error.localizedDescription)")
            }
        }
    }

    /// 为中国设备请求网络权限
     private nonisolated func requestNetworkPermission() async {
           if await SharedPreferences.networkPermissionRequested.get() {
               return
           }
           if !DeviceCensorship.isChinaDevice() {
               await SharedPreferences.networkPermissionRequested.set(true)
               return
           }
           URLSession.shared.dataTask(with: URL(string: "http://captive.apple.com")!) { _, response, _ in
               if let response = response as? HTTPURLResponse {
                   if response.statusCode == 200 {
                       Task {
                           await SharedPreferences.networkPermissionRequested.set(true)
                       }
                   }
               }
           }.resume()
       }
   }
