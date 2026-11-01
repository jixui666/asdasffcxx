import Foundation
import Library
import SwiftUI
import Crisp

/// UUVPN iOS应用程序入口点
/// 管理应用生命周期和视图路由，根据登录状态显示相应界面
@main
struct Application: App {
    /// 应用代理适配器
    @UIApplicationDelegateAdaptor private var appDelegate: ApplicationDelegate
    
    /// VPN扩展环境管理
    @StateObject private var environments = ExtensionEnvironments()
    
    /// 用户登录状态
    @State private var isLoggedIn = UserManager.shared.isUserLoggedIn()
    @State private var isConfigReady = false
    @State private var isLoadingConfig = false
    @State private var didStartConfigLoad = false
    @State private var configError: String?
    @State private var configLoadTask: Task<Bool, Never>?
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if !FilePath.isSharedDirectoryAvailable {
                    VStack(spacing: 12) {
                        Text("安装包权限错误")
                            .font(.headline)
                        Text("无法访问共享容器 \(FilePath.groupName)。请使用包含 App Group 权限的描述文件重新签名并安装应用。")
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if isLoggedIn {
                    if isConfigReady {
                        HomeView(isLoggedIn: $isLoggedIn).environmentObject(environments)
                    } else {
                        VStack(spacing: 16) {
                            if isLoadingConfig || configError == nil {
                                ProgressView()
                                Text("正在读取服务器配置…")
                            } else {
                                Text(configError ?? "服务器配置不可用")
                                Button("重试") {
                                    Task { _ = await ensureConfiguration() }
                                }
                            }
                        }
                        .padding()
                    }
                } else {
                    LoginContentView(
                        isLoggedIn: $isLoggedIn,
                        isConfigurationReady: isConfigReady,
                        isLoadingConfiguration: isLoadingConfig,
                        configurationError: configError,
                        onEnsureConfiguration: {
                            await ensureConfiguration()
                        }
                    )
                }
            }
            .task {
                guard FilePath.isSharedDirectoryAvailable else { return }
                guard !didStartConfigLoad else { return }
                didStartConfigLoad = true
                _ = await ensureConfiguration()
            }
        }
    }

    @MainActor
    private func ensureConfiguration() async -> Bool {
        if isConfigReady { return true }
        if let configLoadTask { return await configLoadTask.value }

        isLoadingConfig = true
        configError = nil

        let task = Task { @MainActor in
            let manager = UserManager.shared
            do {
                _ = try await manager.refreshRemoteConfig()
                isConfigReady = true
            } catch {
                if manager.restoreCachedRemoteConfig() {
                    isConfigReady = true
                } else {
                    configError = "无法获取服务器配置，请检查网络后重试。"
                }
            }

            let crispToken = manager.crispTokenData()
            if isConfigReady && !crispToken.isEmpty {
                CrispSDK.configure(websiteID: crispToken)
            }
            isLoadingConfig = false
            configLoadTask = nil
            return isConfigReady
        }
        configLoadTask = task
        return await task.value
    }
}
