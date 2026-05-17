import SwiftUI
import UIKit

struct CircleFeedView: View {
    let posts: [CirclePost]
    let onTransfer: (CirclePost) -> Void
    let onReport: (CirclePost) -> Void
    let onRefresh: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if posts.isEmpty {
                CircleEmptyFeedView()
            } else {
                HStack(alignment: .top, spacing: 10) {
                    CircleMasonryColumn(
                        posts: columns.left,
                        onTransfer: onTransfer,
                        onReport: onReport
                    )
                    CircleMasonryColumn(
                        posts: columns.right,
                        onTransfer: onTransfer,
                        onReport: onReport
                    )
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .background(CircleFeedStyle.pageBackground)
        .refreshable {
            onRefresh()
        }
    }

    private var columns: (left: [CirclePost], right: [CirclePost]) {
        var left: [CirclePost] = []
        var right: [CirclePost] = []
        var leftHeight: CGFloat = 0
        var rightHeight: CGFloat = 0

        for post in posts {
            let estimatedHeight = CircleFeedStyle.previewHeight(for: post) + 82
            if leftHeight <= rightHeight {
                left.append(post)
                leftHeight += estimatedHeight
            } else {
                right.append(post)
                rightHeight += estimatedHeight
            }
        }

        return (left, right)
    }
}

private struct CircleMasonryColumn: View {
    let posts: [CirclePost]
    let onTransfer: (CirclePost) -> Void
    let onReport: (CirclePost) -> Void

    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(posts) { post in
                CirclePostCard(
                    post: post,
                    onTransfer: { onTransfer(post) },
                    onReport: { onReport(post) }
                )
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CirclePostCard: View {
    let post: CirclePost
    let onTransfer: () -> Void
    let onReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            lockedPreview

            VStack(alignment: .leading, spacing: 7) {
                Text(post.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !post.tags.isEmpty {
                    Text(post.tags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CircleFeedStyle.tint.opacity(0.85))
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    CircleAvatarView(
                        username: post.author.username,
                        avatarKey: post.author.avatarKey,
                        avatarUrl: post.author.avatarUrl
                    )

                    Text(post.author.username)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Button(action: onTransfer) {
                        Text("传输")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CircleFeedStyle.tint)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 4) {
                    Label("\(post.transferCount)", systemImage: "paperplane")
                        .labelStyle(.titleAndIcon)

                    Spacer(minLength: 4)

                    Menu {
                        Button("举报", role: .destructive, action: onReport)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 9)
        }
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 0.5)
        }
        .frame(maxWidth: .infinity)
    }

    private var lockedPreview: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: CircleFeedStyle.palette(for: post),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let previewUrl = post.previewUrl {
                    CircleCachedPreviewImage(
                        cacheKey: post.id,
                        url: previewUrl,
                        seed: CircleFeedStyle.seed(for: post)
                    )
                } else {
                    CircleFeedAbstractArtwork(seed: CircleFeedStyle.seed(for: post))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: CircleFeedStyle.previewHeight(for: post))
            .overlay {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.28)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: "lock.display")
                            .font(.system(size: 18, weight: .semibold))
                        Text("图片仅在土豆片查看")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 3)
                    .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("仅传输")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.72))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(7)
        }
    }

}

private struct CircleCachedPreviewImage: View {
    let cacheKey: String
    let url: URL
    let seed: Int

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    CircleServerPreviewImage(image: Image(uiImage: image))
                } else {
                    CircleFeedAbstractArtwork(seed: seed)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .onAppear(perform: loadIfNeeded)
        .onChange(of: url) { _ in
            loadIfNeeded()
        }
    }

    private func loadIfNeeded() {
        guard !isLoading else { return }
        isLoading = true

        let cacheKey = cacheKey
        let url = url

        Task {
            if let cachedImage = await CircleImageDiskCache.shared.image(for: cacheKey, kind: .preview) {
                await MainActor.run {
                    image = cachedImage
                    isLoading = false
                }
                return
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard
                    let httpResponse = response as? HTTPURLResponse,
                    (200..<300).contains(httpResponse.statusCode),
                    let loadedImage = UIImage(data: data)
                else {
                    await MainActor.run { isLoading = false }
                    return
                }

                CircleImageDiskCache.shared.set(loadedImage, data: data, for: cacheKey, kind: .preview)
                await MainActor.run {
                    image = loadedImage
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
}

private struct CircleServerPreviewImage: View {
    let image: Image

    var body: some View {
        image
            .resizable()
            .scaledToFill()
            .scaleEffect(1.06)
            .blur(radius: 14, opaque: true)
            .saturation(0.9)
            .contrast(0.94)
            .overlay(Color.white.opacity(0.1))
            .overlay(Color.black.opacity(0.12))
            .clipped()
    }
}

private struct CircleCachedAvatarImage: View {
    let cacheKey: String
    let url: URL

    @State private var image: UIImage?
    @State private var isLoading = false

    init(cacheKey: String, url: URL) {
        self.cacheKey = cacheKey
        self.url = url
        _image = State(initialValue: CircleImageDiskCache.shared.cachedImage(for: cacheKey, kind: .avatar))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                EmptyView()
            }
        }
        .onAppear(perform: loadIfNeeded)
        .onChange(of: url) { _ in
            loadIfNeeded()
        }
    }

    private func loadIfNeeded() {
        guard !isLoading else { return }
        isLoading = true

        let cacheKey = cacheKey
        let url = url

        Task {
            if let cachedImage = await CircleImageDiskCache.shared.image(for: cacheKey, kind: .avatar) {
                await MainActor.run {
                    image = cachedImage
                    isLoading = false
                }
                return
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard
                    let httpResponse = response as? HTTPURLResponse,
                    (200..<300).contains(httpResponse.statusCode),
                    let loadedImage = UIImage(data: data)
                else {
                    await MainActor.run { isLoading = false }
                    return
                }

                CircleImageDiskCache.shared.set(loadedImage, data: data, for: cacheKey, kind: .avatar)
                await MainActor.run {
                    image = loadedImage
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
}

private final class CircleImageDiskCache: @unchecked Sendable {
    static let shared = CircleImageDiskCache()

    enum CacheKind {
        case preview
        case avatar

        var directoryName: String {
            switch self {
            case .preview:
                return "previews"
            case .avatar:
                return "avatars"
            }
        }

        var memoryPrefix: String {
            switch self {
            case .preview:
                return "preview"
            case .avatar:
                return "avatar"
            }
        }
    }

    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.xiaogousi.potatocard.circle-image-cache", qos: .utility)
    private let previewLimitBytes: UInt64 = 5 * 1024 * 1024 * 1024
    private let previewTargetBytes: UInt64 = 4 * 1024 * 1024 * 1024
    private let rootURL: URL

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 120 * 1024 * 1024

        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        rootURL = supportURL.appendingPathComponent("PotatoCircleImages", isDirectory: true)
        createDirectoryIfNeeded(directoryURL(for: .preview))
        createDirectoryIfNeeded(directoryURL(for: .avatar))
        excludeFromBackup(rootURL)
        migrateLegacyCacheIfNeeded()
    }

    func image(for key: String, kind: CacheKind) async -> UIImage? {
        let memoryKey = memoryKey(for: key, kind: kind)
        if let memoryImage = cache.object(forKey: memoryKey as NSString) {
            return memoryImage
        }

        return await withCheckedContinuation { continuation in
            ioQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }

                let fileURL = self.fileURL(for: key, kind: kind)
                guard
                    let data = try? Data(contentsOf: fileURL),
                    let image = UIImage(data: data)
                else {
                    continuation.resume(returning: nil)
                    return
                }

                self.touch(fileURL)
                self.cache.setObject(image, forKey: memoryKey as NSString, cost: self.memoryCost(for: image))
                continuation.resume(returning: image)
            }
        }
    }

    func cachedImage(for key: String, kind: CacheKind) -> UIImage? {
        let memoryKey = memoryKey(for: key, kind: kind)
        if let memoryImage = cache.object(forKey: memoryKey as NSString) {
            return memoryImage
        }

        let fileURL = fileURL(for: key, kind: kind)
        guard
            let data = try? Data(contentsOf: fileURL),
            let image = UIImage(data: data)
        else {
            return nil
        }

        touch(fileURL)
        cache.setObject(image, forKey: memoryKey as NSString, cost: memoryCost(for: image))
        return image
    }

    func set(_ image: UIImage, data: Data, for key: String, kind: CacheKind) {
        let memoryKey = memoryKey(for: key, kind: kind)
        cache.setObject(image, forKey: memoryKey as NSString, cost: memoryCost(for: image))

        ioQueue.async { [weak self] in
            guard let self else { return }
            let directoryURL = self.directoryURL(for: kind)
            self.createDirectoryIfNeeded(directoryURL)

            do {
                try data.write(to: self.fileURL(for: key, kind: kind), options: [.atomic])
                if kind == .preview {
                    self.trimPreviewCacheIfNeeded()
                }
            } catch {
                return
            }
        }
    }

    private func memoryCost(for image: UIImage) -> Int {
        let pixelCount = Int(image.size.width * image.scale * image.size.height * image.scale)
        return pixelCount * 4
    }

    private func memoryKey(for key: String, kind: CacheKind) -> String {
        "\(kind.memoryPrefix):\(key)"
    }

    private func directoryURL(for kind: CacheKind) -> URL {
        rootURL.appendingPathComponent(kind.directoryName, isDirectory: true)
    }

    private func fileURL(for key: String, kind: CacheKind) -> URL {
        directoryURL(for: kind).appendingPathComponent(fileName(for: key), isDirectory: false)
    }

    private func fileName(for key: String) -> String {
        key.utf8.map { String(format: "%02x", $0) }.joined() + ".img"
    }

    private func createDirectoryIfNeeded(_ url: URL) {
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func excludeFromBackup(_ url: URL) {
        var mutableURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? mutableURL.setResourceValues(resourceValues)
    }

    private func migrateLegacyCacheIfNeeded() {
        guard let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }

        let legacyRootURL = cachesURL.appendingPathComponent("PotatoCircleImages", isDirectory: true)
        guard legacyRootURL.path != rootURL.path else { return }

        migrateLegacyDirectory(from: legacyRootURL.appendingPathComponent(CacheKind.preview.directoryName, isDirectory: true), to: directoryURL(for: .preview))
        migrateLegacyDirectory(from: legacyRootURL.appendingPathComponent(CacheKind.avatar.directoryName, isDirectory: true), to: directoryURL(for: .avatar))
    }

    private func migrateLegacyDirectory(from sourceURL: URL, to targetURL: URL) {
        guard let files = try? fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil) else {
            return
        }

        createDirectoryIfNeeded(targetURL)
        for sourceFileURL in files {
            let targetFileURL = targetURL.appendingPathComponent(sourceFileURL.lastPathComponent, isDirectory: false)
            guard !fileManager.fileExists(atPath: targetFileURL.path) else { continue }
            try? fileManager.copyItem(at: sourceFileURL, to: targetFileURL)
        }
    }

    private func touch(_ url: URL) {
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private func trimPreviewCacheIfNeeded() {
        let directoryURL = directoryURL(for: .preview)
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let entries: [(url: URL, size: UInt64, date: Date)] = files.compactMap { url in
            guard
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                let size = values.fileSize,
                let date = values.contentModificationDate
            else {
                return nil
            }
            return (url, UInt64(size), date)
        }

        var totalSize = entries.reduce(UInt64(0)) { $0 + $1.size }
        guard totalSize > previewLimitBytes else { return }

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard totalSize > previewTargetBytes else { break }
            try? fileManager.removeItem(at: entry.url)
            totalSize = totalSize > entry.size ? totalSize - entry.size : 0
        }
    }
}

private struct CircleFeedAbstractArtwork: View {
    let seed: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.32))
                    .frame(width: proxy.size.width * 0.58, height: proxy.size.width * 0.58)
                    .offset(x: proxy.size.width * offsetA, y: -proxy.size.height * 0.18)

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: proxy.size.width * 0.64, height: proxy.size.height * 0.42)
                    .rotationEffect(.degrees(Double(seed % 18) - 9))
                    .offset(x: -proxy.size.width * 0.16, y: proxy.size.height * 0.16)

                Capsule()
                    .fill(Color.black.opacity(0.10))
                    .frame(width: proxy.size.width * 0.45, height: 12)
                    .offset(x: proxy.size.width * 0.08, y: proxy.size.height * 0.26)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var offsetA: CGFloat {
        seed.isMultiple(of: 2) ? 0.18 : -0.14
    }
}

private struct CircleAvatarView: View {
    let username: String
    let avatarKey: String
    let avatarUrl: URL?

    var body: some View {
        ZStack {
            placeholder

            if let avatarUrl {
                CircleCachedAvatarImage(cacheKey: avatarKey, url: avatarUrl)
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(Circle())
    }

    private var initial: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0) } ?? "土"
    }

    private var placeholder: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: CircleFeedStyle.avatarPalette(seed: CircleFeedStyle.seed(for: avatarKey)),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(initial)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

private struct CircleEmptyFeedView: View {
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(CircleFeedStyle.tint.opacity(0.10))
                    .frame(width: 76, height: 76)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(CircleFeedStyle.tint)
            }

            VStack(spacing: 6) {
                Text("还没有圈子作品")
                    .font(.system(size: 18, weight: .semibold))
                Text("发布第一张照片，让其他人传输到土豆片查看。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 120)
    }
}

private enum CircleFeedStyle {
    static let tint = Color(red: 0.86, green: 0.16, blue: 0.22)
    static let pageBackground = Color(red: 0.97, green: 0.97, blue: 0.96)

    static func seed(for post: CirclePost) -> Int {
        seed(for: post.id + post.title + post.author.username)
    }

    static func seed(for text: String) -> Int {
        var value: UInt32 = 2_166_136_261
        for scalar in text.unicodeScalars {
            value = (value ^ UInt32(scalar.value)) &* 16_777_619
        }
        return Int(value % 10_000)
    }

    static func previewHeight(for post: CirclePost) -> CGFloat {
        let heights: [CGFloat] = [138, 166, 194, 222]
        return heights[seed(for: post) % heights.count]
    }

    static func palette(for post: CirclePost) -> [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.86, green: 0.79, blue: 0.69), Color(red: 0.48, green: 0.62, blue: 0.52), Color(red: 0.20, green: 0.30, blue: 0.25)],
            [Color(red: 0.90, green: 0.78, blue: 0.80), Color(red: 0.62, green: 0.52, blue: 0.58), Color(red: 0.30, green: 0.28, blue: 0.32)],
            [Color(red: 0.86, green: 0.88, blue: 0.90), Color(red: 0.55, green: 0.63, blue: 0.68), Color(red: 0.33, green: 0.38, blue: 0.42)],
            [Color(red: 0.93, green: 0.88, blue: 0.75), Color(red: 0.70, green: 0.55, blue: 0.30), Color(red: 0.40, green: 0.31, blue: 0.18)]
        ]
        return palettes[seed(for: post) % palettes.count]
    }

    static func avatarPalette(seed: Int) -> [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.94, green: 0.66, blue: 0.58), Color(red: 0.82, green: 0.23, blue: 0.32)],
            [Color(red: 0.56, green: 0.68, blue: 0.58), Color(red: 0.25, green: 0.46, blue: 0.36)],
            [Color(red: 0.72, green: 0.62, blue: 0.86), Color(red: 0.38, green: 0.34, blue: 0.72)],
            [Color(red: 0.78, green: 0.62, blue: 0.38), Color(red: 0.46, green: 0.32, blue: 0.18)]
        ]
        return palettes[seed % palettes.count]
    }
}
