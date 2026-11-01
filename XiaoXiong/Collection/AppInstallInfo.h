#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 移植自 3105 的 AppIconHelper：只用 LSApplicationWorkspace /
/// MobileInstallation 两个私有入口，提供采集管线需要的安装信息。
/// 返回 bundleID -> @{ @"name": NSString, @"container": NSString }。
NSDictionary<NSString *, NSDictionary *> *installedAppInfo(void);

/// 单个 bundleID 的安装信息：@{ @"name": ..., @"version": ..., @"container": ..., @"found": @YES }。
NSDictionary *appInfoForBundleID(NSString *bundleID);

NS_ASSUME_NONNULL_END
