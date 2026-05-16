import SwiftUI

struct CircleView: View {
    @StateObject private var sessionStore = CircleSessionStore()
    @StateObject private var transferCoordinator: CircleTransferCoordinator
    @State private var posts: [CirclePost] = []
    @State private var errorMessage: String?
    @State private var isComposerPresented = false
    @State private var isLoadingPosts = false

    private let apiClient: CircleAPIClient

    init(apiClient: CircleAPIClient = CircleView.defaultAPIClient()) {
        self.apiClient = apiClient
        _transferCoordinator = StateObject(wrappedValue: CircleTransferCoordinator(apiClient: apiClient))
    }

    var body: some View {
        Group {
            if sessionStore.isRegistered {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if isLoadingPosts {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        CircleFeedView(posts: posts, onTransfer: handleTransfer, onReport: handleReport)
                    }
                    if let visibleErrorMessage {
                        Text(visibleErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                    }
                }
            } else {
                CircleRegistrationView(sessionStore: sessionStore, apiClient: apiClient)
            }
        }
        .onAppear {
            sessionStore.loadFromStorage()
            loadPostsIfNeeded()
        }
        .onChange(of: sessionStore.isRegistered) { isRegistered in
            guard isRegistered else { return }
            loadPostsIfNeeded()
        }
        .sheet(item: $transferCoordinator.transferRequest) { request in
            TransferSheetView(
                sourceImage: request.image,
                title: request.post.title,
                editStateKey: nil,
                onTransferSucceeded: {
                    transferCoordinator.transferRequest = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isComposerPresented) {
            CirclePostComposerView { imageData, title, tags in
                publish(imageData: imageData, title: title, tags: tags)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("圈子")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Spacer()
            Button("发布") {
                isComposerPresented = true
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }

    private var visibleErrorMessage: String? {
        transferCoordinator.errorMessage ?? errorMessage
    }

    private func handleTransfer(_ post: CirclePost) {
        transferCoordinator.beginTransfer(post: post)
    }

    private func handleReport(_ post: CirclePost) {
        errorMessage = "已提交举报：\(post.title)"
    }

    private func loadPostsIfNeeded() {
        guard sessionStore.isRegistered, posts.isEmpty else { return }
        refreshPosts()
    }

    private func refreshPosts() {
        isLoadingPosts = true
        errorMessage = nil
        Task {
            do {
                posts = try await apiClient.fetchPosts()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoadingPosts = false
        }
    }

    private func publish(imageData: Data, title: String, tags: [String]) {
        Task {
            do {
                try await apiClient.createPost(imageData: imageData, title: title, tags: tags)
                posts = try await apiClient.fetchPosts()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func defaultAPIClient() -> CircleAPIClient {
        CircleAPIClient(
            baseURL: URL(string: "http://localhost:3000")!,
            tokenProvider: {
                let token = UserDefaults.standard.string(forKey: "circleAccessToken") ?? ""
                return token.isEmpty ? nil : token
            }
        )
    }
}
