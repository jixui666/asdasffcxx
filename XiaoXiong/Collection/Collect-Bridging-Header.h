#import <CommonCrypto/CommonCrypto.h>

// 采集链路（移植自 3105）暴露给 Swift 的 C / ObjC 接口。

#import "mcm_bridge.h"
#import "bad_query.h"
#import "AppInstallInfo.h"

// MCM 租约激活依赖 containermanager 的 sandbox extension，
// Swift 侧只用封装的 container_* 接口，这里保留底层 consume/release 声明。
extern int sandbox_extension_consume(const char *token);
