import SwiftUI

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
                    CircleMasonryColumn(posts: columns.left, onTransfer: onTransfer, onReport: onReport)
                    CircleMasonryColumn(posts: columns.right, onTransfer: onTransfer, onReport: onReport)
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
                    CircleAvatarView(username: post.author.username, avatarKey: post.author.avatarKey)

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
    }

    private var lockedPreview: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: CircleFeedStyle.palette(for: post),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: CircleFeedStyle.previewHeight(for: post))
                .overlay(alignment: .center) {
                    CircleFeedAbstractArtwork(seed: CircleFeedStyle.seed(for: post))
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

    var body: some View {
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
        .frame(width: 20, height: 20)
    }

    private var initial: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0) } ?? "土"
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
