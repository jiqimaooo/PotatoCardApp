import SwiftUI

struct CircleView: View {
    @EnvironmentObject private var bleService: BleTransferService
    @StateObject private var sessionStore = CircleSessionStore()
    @StateObject private var transferCoordinator: CircleTransferCoordinator
    @State private var posts: [CirclePost] = []
    @State private var errorMessage: String?
    @State private var isComposerPresented = false
    @State private var isLoadingPosts = false

    private let apiClient: CircleAPIClient

    private var sessionAPIClient: CircleAPIClient {
        var client = apiClient
        client.tokenProvider = { sessionStore.token }
        return client
    }

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
                        CircleFeedView(
                            posts: posts,
                            onTransfer: handleTransfer,
                            onReport: handleReport,
                            onRefresh: refreshPosts
                        )
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
        .sheet(isPresented: $isComposerPresented) {
            CirclePostComposerView { imageData, title, tags in
                publish(imageData: imageData, title: title, tags: tags)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            HStack(spacing: 20) {
                CircleFeedTab(title: "发现", isSelected: true)
                CircleFeedTab(title: "关注", isSelected: false)
                CircleFeedTab(title: "最新", isSelected: false)
            }
            Spacer()

            Button {
                isComposerPresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color(red: 0.86, green: 0.16, blue: 0.22), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("发布")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
    }

    private var visibleErrorMessage: String? {
        transferCoordinator.errorMessage ?? bleService.errorMessage ?? errorMessage
    }

    private func handleTransfer(_ post: CirclePost) {
        Task {
            do {
                let accessToken = try await validAccessToken()
                transferCoordinator.beginTransfer(post: post, apiClient: sessionAPIClient, accessToken: accessToken, bleService: bleService)
            } catch {
                handleSessionError(error)
            }
        }
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
                posts = try await fetchPostsWithRefresh()
            } catch {
                handleSessionError(error)
            }
            isLoadingPosts = false
        }
    }

    private func publish(imageData: Data, title: String, tags: [String]) {
        Task {
            do {
                try await createPostWithRefresh(imageData: imageData, title: title, tags: tags)
                posts = try await fetchPostsWithRefresh()
            } catch {
                handleSessionError(error)
            }
        }
    }

    private func fetchPostsWithRefresh() async throws -> [CirclePost] {
        _ = try await validAccessToken()
        do {
            return try await sessionAPIClient.fetchPosts()
        } catch CircleAPIError.unauthorized {
            _ = try await validAccessToken(forceRefresh: true)
            return try await sessionAPIClient.fetchPosts()
        }
    }

    private func createPostWithRefresh(imageData: Data, title: String, tags: [String]) async throws {
        let accessToken = try await validAccessToken()
        do {
            try await sessionAPIClient.createPost(imageData: imageData, title: title, tags: tags, accessToken: accessToken)
        } catch CircleAPIError.unauthorized {
            let refreshedToken = try await validAccessToken(forceRefresh: true)
            try await sessionAPIClient.createPost(imageData: imageData, title: title, tags: tags, accessToken: refreshedToken)
        }
    }

    private func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let refreshToken = sessionStore.refreshToken else {
            throw CircleAPIError.missingAuthToken
        }

        if forceRefresh || sessionStore.shouldRefreshAccessToken {
            let session = try await apiClient.refreshSession(refreshToken: refreshToken)
            sessionStore.saveSession(session)
        }

        guard let accessToken = sessionStore.token else {
            throw CircleAPIError.missingAuthToken
        }
        return accessToken
    }

    private func handleExpiredSession() {
        errorMessage = CircleAPIError.missingAuthToken.localizedDescription
        sessionStore.signOut()
        isComposerPresented = false
    }

    private func handleSessionError(_ error: Error) {
        if case CircleAPIError.unauthorized = error {
            handleExpiredSession()
            return
        }
        if case CircleAPIError.missingAuthToken = error {
            handleExpiredSession()
            return
        }
        errorMessage = error.localizedDescription
    }

    private static func defaultAPIClient() -> CircleAPIClient {
        CircleAPIClient(
            baseURL: URL(string: "https://potato.xiaogousi.online")!,
            tokenProvider: {
                let token = UserDefaults.standard.string(forKey: "circleAccessToken") ?? ""
                return token.isEmpty ? nil : token
            }
        )
    }
}

private struct CircleFeedTab: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 17, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)

            Capsule()
                .fill(isSelected ? Color(red: 0.86, green: 0.16, blue: 0.22) : Color.clear)
                .frame(width: 24, height: 3)
        }
        .contentShape(Rectangle())
    }
}
