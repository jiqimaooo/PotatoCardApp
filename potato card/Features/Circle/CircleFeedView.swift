import SwiftUI

struct CircleFeedView: View {
    let posts: [CirclePost]
    let onTransfer: (CirclePost) -> Void
    let onReport: (CirclePost) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 14) {
                ForEach(posts) { post in
                    CirclePostCard(
                        post: post,
                        onTransfer: { onTransfer(post) },
                        onReport: { onReport(post) }
                    )
                }
            }
            .padding(24)
        }
    }
}

private struct CirclePostCard: View {
    let post: CirclePost
    let onTransfer: () -> Void
    let onReport: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            lockedPreview

            VStack(alignment: .leading, spacing: 8) {
                Text(post.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(post.author.username)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !post.tags.isEmpty {
                    Text(post.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Button("传输到设备", action: onTransfer)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)

                    Button("举报", action: onReport)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var lockedPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 72, height: 108)
            Image(systemName: "lock.display")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}
