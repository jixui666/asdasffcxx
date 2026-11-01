import Foundation

public enum FilePath {
    #if os(iOS)
        public static let packageName: String = {
            let bundleID = Bundle.main.bundleIdentifier ?? ""
            for suffix in [".extension", ".intents"] where bundleID.hasSuffix(suffix) {
                return String(bundleID.dropLast(suffix.count))
            }
            return bundleID
        }()
    #else
        public static let packageName = "com.uuvpn.appleaman"
    #endif
}

public extension FilePath {
    private static let sharedContainer: (name: String, directory: URL?) = {
        let configuredName = Bundle.main.object(forInfoDictionaryKey: "UUVPNAppGroupIdentifier") as? String
        let derivedName = "group.\(packageName)"
        let candidates = [configuredName, derivedName].compactMap { $0 }
        for name in candidates where name.hasPrefix("group.") && name != "group." {
            if let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: name) {
                return (name, directory)
            }
        }
        return (candidates.first ?? derivedName, nil)
    }()

    static let groupName = sharedContainer.name

    private static let defaultSharedDirectory: URL! = sharedContainer.directory

    /// The main app and packet tunnel must both be signed for this App Group.
    static var isSharedDirectoryAvailable: Bool { defaultSharedDirectory != nil }

    #if os(iOS)
        static let sharedDirectory = defaultSharedDirectory!
    #elseif os(tvOS)
        static let sharedDirectory = defaultSharedDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
    #elseif os(macOS)
        static var sharedDirectory: URL! = defaultSharedDirectory
    #endif

    #if os(iOS)
        static let cacheDirectory = sharedDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
    #elseif os(tvOS)
        static let cacheDirectory = sharedDirectory
    #elseif os(macOS)
        static var cacheDirectory: URL {
            sharedDirectory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true)
        }
    #endif

    #if os(macOS)
        static var workingDirectory: URL {
            cacheDirectory.appendingPathComponent("Working", isDirectory: true)
        }
    #else
        static let workingDirectory = cacheDirectory.appendingPathComponent("Working", isDirectory: true)

    #endif

    static var iCloudDirectory = FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents", isDirectory: true) ?? URL(string: "stub")!
}

public extension URL {
    var fileName: String {
        var path = relativePath
        if let index = path.lastIndex(of: "/") {
            path = String(path[path.index(index, offsetBy: 1)...])
        }
        return path
    }
}
