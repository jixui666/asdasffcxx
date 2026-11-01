#import "AppInstallInfo.h"
#import <objc/message.h>
#import <dlfcn.h>

// 移植自 3105/helpers/AppIconHelper.m 的 installedAppInfo / appInfoForBundleID。
// LSApplicationWorkspace 枚举失败时退回 MobileInstallation 查询，与 3105 一致。

static NSDictionary<NSString *, NSDictionary *> *appsFromWorkspace(void) {
    NSMutableDictionary<NSString *, NSDictionary *> *result = [NSMutableDictionary dictionary];

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) return result;
    SEL defaultWorkspaceSel = NSSelectorFromString(@"defaultWorkspace");
    if (![workspaceClass respondsToSelector:defaultWorkspaceSel]) return result;
    id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultWorkspaceSel);
    if (!workspace) return result;

    NSArray *apps = nil;
    for (NSString *selectorName in @[@"allApplications", @"allInstalledApplications"]) {
        SEL allAppsSel = NSSelectorFromString(selectorName);
        if (![workspace respondsToSelector:allAppsSel]) continue;
        id candidate = ((id (*)(id, SEL))objc_msgSend)(workspace, allAppsSel);
        if ([candidate isKindOfClass:[NSArray class]] && [candidate count] > 0) {
            apps = candidate;
            break;
        }
    }
    if (apps.count == 0) return result;

    for (id app in apps) {
        @autoreleasepool {
            NSString *bundleID = nil;
            for (NSString *selectorName in @[@"bundleIdentifier", @"applicationIdentifier"]) {
                SEL bundleSel = NSSelectorFromString(selectorName);
                if (![app respondsToSelector:bundleSel]) continue;
                id value = ((id (*)(id, SEL))objc_msgSend)(app, bundleSel);
                if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
                    bundleID = value;
                    break;
                }
            }
            if (bundleID.length == 0) continue;

            NSString *name = nil;
            for (NSString *selectorName in @[@"localizedName", @"localizedShortName"]) {
                SEL nameSel = NSSelectorFromString(selectorName);
                if (![app respondsToSelector:nameSel]) continue;
                id value = ((id (*)(id, SEL))objc_msgSend)(app, nameSel);
                if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
                    name = value;
                    break;
                }
            }
            if (name.length == 0) name = bundleID;

            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            entry[@"name"] = name;
            for (NSString *selectorName in @[@"dataContainerURL", @"containerURL"]) {
                SEL containerSel = NSSelectorFromString(selectorName);
                if (![app respondsToSelector:containerSel]) continue;
                id containerValue = ((id (*)(id, SEL))objc_msgSend)(app, containerSel);
                NSString *containerPath = [containerValue isKindOfClass:[NSURL class]]
                    ? [containerValue path] : containerValue;
                if ([containerPath isKindOfClass:[NSString class]] && containerPath.length > 0) {
                    entry[@"container"] = containerPath;
                    break;
                }
            }
            for (NSString *selectorName in @[@"shortVersionString"]) {
                SEL versionSel = NSSelectorFromString(selectorName);
                if (![app respondsToSelector:versionSel]) continue;
                id value = ((id (*)(id, SEL))objc_msgSend)(app, versionSel);
                if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
                    entry[@"version"] = value;
                    break;
                }
            }
            result[bundleID] = entry;
        }
    }
    return result;
}

typedef NSDictionary *(*MILookupFn)(NSString *, NSError **);

static NSDictionary<NSString *, NSDictionary *> *appsFromMobileInstallation(void) {
    NSMutableDictionary<NSString *, NSDictionary *> *result = [NSMutableDictionary dictionary];

    void *handle = dlopen("/usr/lib/libMobileInstallation.dylib", RTLD_NOW | RTLD_LOCAL);
    if (!handle) return result;
    MILookupFn lookup = (MILookupFn)dlsym(handle, "MobileInstallationLookup");
    if (!lookup) {
        dlclose(handle);
        return result;
    }
    NSError *error = nil;
    NSDictionary *raw = lookup(nil, &error);
    if ([raw isKindOfClass:[NSDictionary class]]) {
        for (NSString *bundleID in raw) {
            NSDictionary *info = raw[bundleID];
            if (![info isKindOfClass:[NSDictionary class]]) continue;
            NSString *name = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: bundleID;
            NSString *container = info[@"Container"];
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            entry[@"name"] = [name isKindOfClass:[NSString class]] ? name : bundleID;
            if ([container isKindOfClass:[NSString class]] && container.length > 0) {
                entry[@"container"] = container;
            }
            NSString *version = info[@"CFBundleShortVersionString"];
            if ([version isKindOfClass:[NSString class]] && version.length > 0) {
                entry[@"version"] = version;
            }
            result[bundleID] = entry;
        }
    }
    dlclose(handle);
    return result;
}

NSDictionary<NSString *, NSDictionary *> *installedAppInfo(void) {
    NSDictionary *workspace = appsFromWorkspace();
    if (workspace.count > 0) return workspace;
    return appsFromMobileInstallation();
}

static NSString *stringForFirstKey(NSDictionary *dictionary, NSArray<NSString *> *keys) {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
    for (NSString *key in keys) {
        id value = dictionary[key];
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    }
    return nil;
}

NSDictionary *appInfoForBundleID(NSString *bundleID) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"name"] = bundleID;

    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    if (!proxyClass) return result;
    SEL appProxySel = NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (![proxyClass respondsToSelector:appProxySel]) return result;
    id proxy = ((id (*)(id, SEL, id))objc_msgSend)(proxyClass, appProxySel, bundleID);
    if (!proxy) return result;

    BOOL matchesRequestedIdentifier = NO;
    for (NSString *selectorName in @[@"applicationIdentifier", @"bundleIdentifier"]) {
        SEL identifierSel = NSSelectorFromString(selectorName);
        if (![proxy respondsToSelector:identifierSel]) continue;
        id value = ((id (*)(id, SEL))objc_msgSend)(proxy, identifierSel);
        if ([value isKindOfClass:[NSString class]] && [value isEqualToString:bundleID]) {
            matchesRequestedIdentifier = YES;
        }
    }
    if (!matchesRequestedIdentifier) return result;
    result[@"found"] = @YES;

    NSURL *bundleURL = nil;
    SEL bundleURLSel = NSSelectorFromString(@"bundleURL");
    if ([proxy respondsToSelector:bundleURLSel]) {
        id value = ((id (*)(id, SEL))objc_msgSend)(proxy, bundleURLSel);
        if ([value isKindOfClass:[NSURL class]]) bundleURL = value;
    }

    NSBundle *applicationBundle = bundleURL ? [NSBundle bundleWithURL:bundleURL] : nil;
    NSDictionary *localizedInfo = applicationBundle.localizedInfoDictionary;
    NSDictionary *bundleInfo = applicationBundle.infoDictionary;
    NSString *bundleName = stringForFirstKey(localizedInfo, @[@"CFBundleDisplayName", @"CFBundleName"]);
    if (bundleName.length == 0) {
        bundleName = stringForFirstKey(bundleInfo, @[@"CFBundleDisplayName", @"CFBundleName"]);
    }
    if (bundleName.length > 0) result[@"name"] = bundleName;

    if ([result[@"name"] isEqualToString:bundleID]) {
        for (NSString *selectorName in @[@"localizedName", @"localizedShortName"]) {
            SEL nameSel = NSSelectorFromString(selectorName);
            if (![proxy respondsToSelector:nameSel]) continue;
            NSString *name = ((id (*)(id, SEL))objc_msgSend)(proxy, nameSel);
            if ([name isKindOfClass:[NSString class]] && name.length > 0) {
                result[@"name"] = name;
                break;
            }
        }
    }

    NSString *bundleVersion = stringForFirstKey(bundleInfo, @[@"CFBundleShortVersionString"]);
    if (bundleVersion.length > 0) result[@"version"] = bundleVersion;
    if (!result[@"version"]) {
        SEL versionSel = NSSelectorFromString(@"shortVersionString");
        if ([proxy respondsToSelector:versionSel]) {
            NSString *version = ((id (*)(id, SEL))objc_msgSend)(proxy, versionSel);
            if ([version isKindOfClass:[NSString class]] && version.length > 0) {
                result[@"version"] = version;
            }
        }
    }

    for (NSString *selectorName in @[@"dataContainerURL", @"containerURL"]) {
        SEL containerSel = NSSelectorFromString(selectorName);
        if (![proxy respondsToSelector:containerSel]) continue;
        id value = ((id (*)(id, SEL))objc_msgSend)(proxy, containerSel);
        NSString *path = [value isKindOfClass:[NSURL class]] ? [value path] : value;
        if ([path isKindOfClass:[NSString class]] && path.length > 0) {
            result[@"container"] = path;
            break;
        }
    }

    return result;
}
