import SwiftUI

struct CircleView: View {
    @StateObject private var sessionStore = CircleSessionStore()
    @State private var posts: [CirclePost] = []
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if sessionStore.isRegistered {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    CircleFeedView(posts: posts, onTransfer: handleTransfer, onReport: handleReport)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                    }
                }
            } else {
                CircleRegistrationView(sessionStore: sessionStore)
            }
        }
        .onAppear {
            sessionStore.loadFromStorage()
        }
    }

    private var header: some View {
        HStack {
            Text("圈子")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Spacer()
            Button("发布") {
                errorMessage = "请先完成作品信息后再发布"
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }

    private func handleTransfer(_ post: CirclePost) {
        errorMessage = "正在准备传输：\(post.title)"
    }

    private func handleReport(_ post: CirclePost) {
        errorMessage = "已提交举报：\(post.title)"
    }
}
