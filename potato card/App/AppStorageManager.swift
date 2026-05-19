import Foundation

struct AppStorageUsage: Equatable {
    let currentCacheBytes: Int64
    let clearableCacheBytes: Int64
}

enum AppStorageManager {
    // 这些目录虽然位于 Caches，但承载用户图库或待推送任务，清理缓存时必须保留。
    nonisolated private static let protectedCacheDirectoryNames: Set<String> = [
        "GalleryPhotoCache",
        "PendingCardPush"
    ]

    nonisolated static func loadUsage() -> AppStorageUsage {
        let fileManager = FileManager.default
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        let temporaryURL = fileManager.temporaryDirectory
        let circleImagesURL = applicationSupportURL()?.appendingPathComponent("PotatoCircleImages", isDirectory: true)

        let currentCacheBytes =
            bytes(at: cachesURL) +
            bytes(at: temporaryURL) +
            bytes(at: circleImagesURL)

        let clearableCacheBytes =
            clearableBytesInCaches(cachesURL) +
            bytes(at: temporaryURL) +
            bytes(at: circleImagesURL)

        return AppStorageUsage(
            currentCacheBytes: currentCacheBytes,
            clearableCacheBytes: clearableCacheBytes
        )
    }

    nonisolated static func clearCache() {
        let fileManager = FileManager.default

        if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            removeClearableChildren(in: cachesURL, protectedNames: protectedCacheDirectoryNames)
        }

        removeAllChildren(in: fileManager.temporaryDirectory)

        if let circleImagesURL = applicationSupportURL()?.appendingPathComponent("PotatoCircleImages", isDirectory: true) {
            try? fileManager.removeItem(at: circleImagesURL)
        }

        URLCache.shared.removeAllCachedResponses()
    }

    nonisolated static func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: max(0, bytes))
    }

    private nonisolated static func clearableBytesInCaches(_ cachesURL: URL?) -> Int64 {
        guard let cachesURL else { return 0 }
        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(
            at: cachesURL,
            includingPropertiesForKeys: [.isDirectoryKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return children
            .filter { !protectedCacheDirectoryNames.contains($0.lastPathComponent) }
            .reduce(Int64(0)) { $0 + bytes(at: $1) }
    }

    private nonisolated static func removeClearableChildren(in directoryURL: URL, protectedNames: Set<String>) {
        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for child in children where !protectedNames.contains(child.lastPathComponent) {
            try? fileManager.removeItem(at: child)
        }
    }

    private nonisolated static func removeAllChildren(in directoryURL: URL) {
        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for child in children {
            try? fileManager.removeItem(at: child)
        }
    }

    private nonisolated static func bytes(at url: URL?) -> Int64 {
        guard let url else { return 0 }
        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }

        if !isDirectory.boolValue {
            return allocatedSize(of: url)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += allocatedSize(of: fileURL)
        }
        return total
    }

    private nonisolated static func allocatedSize(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileAllocatedSizeKey, .totalFileAllocatedSizeKey])
        let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0
        return Int64(size)
    }

    private nonisolated static func applicationSupportURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }
}
