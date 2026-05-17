import SwiftUI

struct CircleView: View {
    @EnvironmentObject private var bleService: BleTransferService
    @StateObject private var sessionStore = CircleSessionStore()
    @StateObject private var transferCoordinator: CircleTransferCoordinator
    @State private var posts: [CirclePost] = []
    @State private var isComposerPresented = false
    @State private var isLoadingPosts = false
    @State private var transferStatusVisibilityTask: Task<Void, Never>?
    @State private var isTransferStatusVisible = false
    @State private var toastMessage: CircleToastMessage?
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var publishStatusVisibilityTask: Task<Void, Never>?
    @State private var publishStatusState: CirclePublishStatusToast.StateStyle = .posting
    @State private var isPublishStatusVisible = false

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
                ZStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        if showsFullPageLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ZStack(alignment: .top) {
                                CircleFeedView(
                                    posts: posts,
                                    onTransfer: handleTransfer,
                                    onReport: handleReport,
                                    onRefresh: refreshPosts
                                )

                                if isLoadingPosts {
                                    CircleFeedTopLoadingView()
                                        .padding(.top, 8)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                        }
                    }

                    VStack(spacing: 10) {
                        if let toastMessage {
                            CircleToastView(message: toastMessage)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        if isPublishStatusVisible {
                            CirclePublishStatusToast(state: publishStatusState)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        if isTransferStatusVisible {
                            CircleTransferStatusToast(
                                state: transferStatusState,
                                title: transferStatusTitle,
                                subtitle: transferStatusSubtitle,
                                progress: transferProgressValue
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isTransferStatusVisible)
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: toastMessage)
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isPublishStatusVisible)
                .animation(.easeInOut(duration: 0.18), value: isLoadingPosts)
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
        .onReceive(NotificationCenter.default.publisher(for: CircleSessionStore.didSignOutNotification)) { _ in
            posts = []
            toastMessage = nil
            isPublishStatusVisible = false
            isComposerPresented = false
            sessionStore.loadFromStorage()
        }
        .onChange(of: transferCoordinator.isPreparingTransfer) { isPreparing in
            if isPreparing { showTransferStatus() }
        }
        .onChange(of: bleService.transferPhase) { phase in
            handleTransferPhaseChange(phase)
        }
        .onChange(of: transferCoordinator.errorMessage) { message in
            guard let message, !message.isEmpty else { return }
            showToast(message, style: .error)
        }
        .onChange(of: bleService.errorMessage) { message in
            guard let message, !message.isEmpty else { return }
            showToast(message, style: .error)
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
                unavailableFeedTab(title: "关注")
                unavailableFeedTab(title: "最新")
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

    private func unavailableFeedTab(title: String) -> some View {
        Button {
            showToast("暂未开放，敬请期待", style: .info)
        } label: {
            CircleFeedTab(title: title, isSelected: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，暂未开放")
    }

    private var transferStatusState: CircleTransferStatusToast.StateStyle {
        if transferCoordinator.isPreparingTransfer { return .preparing }
        switch bleService.transferPhase {
        case .preparing:
            return .preparing
        case .transferring:
            return .transferring
        case .succeeded:
            return .succeeded
        case .failed:
            return .failed
        case .idle:
            return .preparing
        }
    }

    private var transferStatusTitle: String {
        if transferCoordinator.isPreparingTransfer { return "正在获取圈子图片" }
        switch bleService.transferPhase {
        case .preparing:
            return "正在准备传输"
        case .transferring:
            return "正在传输到土豆片"
        case .succeeded:
            return "传输完成"
        case .failed:
            return "传输失败"
        case .idle:
            return "准备传输"
        }
    }

    private var transferStatusSubtitle: String {
        if transferCoordinator.isPreparingTransfer { return "图片不会在 App 内公开查看" }
        switch bleService.transferPhase {
        case .preparing:
            return "正在生成适合墨水屏的图片"
        case .transferring:
            return "\(transferProgressPercent)%"
        case .succeeded:
            return "已推送到当前设备"
        case .failed(let message):
            return message
        case .idle:
            return "等待设备响应"
        }
    }

    private var transferProgressValue: Double {
        if transferCoordinator.isPreparingTransfer { return 0.08 }
        switch bleService.transferPhase {
        case .preparing:
            return max(0.08, bleService.transferProgress)
        case .transferring, .succeeded:
            return bleService.transferProgress
        case .failed:
            return max(0.08, bleService.transferProgress)
        case .idle:
            return 0
        }
    }

    private var transferProgressPercent: Int {
        min(100, max(0, Int((transferProgressValue * 100).rounded())))
    }

    private var showsFullPageLoading: Bool {
        isLoadingPosts && posts.isEmpty
    }

    private func handleTransfer(_ post: CirclePost) {
        showTransferStatus()
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
        showToast("已提交举报：\(post.title)", style: .success)
    }

    private func loadPostsIfNeeded() {
        guard sessionStore.isRegistered, posts.isEmpty else { return }
        restoreCachedPostsIfNeeded()
        refreshPosts()
    }

    private func refreshPosts() {
        guard !isLoadingPosts else { return }
        isLoadingPosts = true
        Task {
            do {
                let fetchedPosts = try await fetchPostsWithRefresh()
                posts = fetchedPosts
                saveCachedPosts(fetchedPosts)
            } catch {
                handleSessionError(error)
            }
            isLoadingPosts = false
        }
    }

    private func publish(imageData: Data, title: String, tags: [String]) {
        showPublishStatus(.posting)
        Task {
            do {
                try await createPostWithRefresh(imageData: imageData, title: title, tags: tags)
                showPublishStatus(.succeeded)
                do {
                    let fetchedPosts = try await fetchPostsWithRefresh()
                    posts = fetchedPosts
                    saveCachedPosts(fetchedPosts)
                } catch {
                    showToast("发布成功，但刷新失败：\(error.localizedDescription)", style: .error)
                }
                hidePublishStatus(after: 2)
            } catch {
                showPublishStatus(.failed(error.localizedDescription))
                hidePublishStatus(after: 3)
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

    private func restoreCachedPostsIfNeeded() {
        guard posts.isEmpty, let userID = sessionStore.profile?.id else { return }
        guard let cachedPosts = CircleFeedPostCache.shared.loadPosts(for: userID) else { return }
        posts = cachedPosts
    }

    private func saveCachedPosts(_ posts: [CirclePost]) {
        guard let userID = sessionStore.profile?.id else { return }
        CircleFeedPostCache.shared.savePosts(posts, for: userID)
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
        showToast(CircleAPIError.missingAuthToken.localizedDescription, style: .error)
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
        let message = error.localizedDescription
        showToast(message, style: .error)
    }

    private func showTransferStatus() {
        transferStatusVisibilityTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isTransferStatusVisible = true
        }
    }

    private func hideTransferStatus(after seconds: UInt64) {
        transferStatusVisibilityTask?.cancel()
        transferStatusVisibilityTask = Task {
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.22)) {
                    isTransferStatusVisible = false
                }
            }
        }
    }

    private func handleTransferPhaseChange(_ phase: TransferPhase) {
        switch phase {
        case .preparing, .transferring:
            showTransferStatus()
        case .succeeded, .failed:
            showTransferStatus()
            hideTransferStatus(after: 3)
        case .idle:
            break
        }
    }

    private func showPublishStatus(_ state: CirclePublishStatusToast.StateStyle) {
        publishStatusVisibilityTask?.cancel()
        publishStatusState = state
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isPublishStatusVisible = true
        }
    }

    private func hidePublishStatus(after seconds: UInt64) {
        publishStatusVisibilityTask?.cancel()
        publishStatusVisibilityTask = Task {
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.22)) {
                    isPublishStatusVisible = false
                }
            }
        }
    }

    private func showToast(_ message: String, style: CircleToastMessage.Style) {
        toastDismissTask?.cancel()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            toastMessage = CircleToastMessage(text: message, style: style)
        }

        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.22)) {
                    toastMessage = nil
                }
            }
        }
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

private final class CircleFeedPostCache {
    static let shared = CircleFeedPostCache()

    private let fileManager = FileManager.default
    private let rootURL: URL

    private init() {
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        rootURL = supportURL.appendingPathComponent("PotatoCircleFeed", isDirectory: true)
        createDirectoryIfNeeded(rootURL)
        excludeFromBackup(rootURL)
    }

    func loadPosts(for userID: String) -> [CirclePost]? {
        let fileURL = fileURL(for: userID)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([CirclePost].self, from: data)
    }

    func savePosts(_ posts: [CirclePost], for userID: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(posts) else { return }

        createDirectoryIfNeeded(rootURL)
        try? data.write(to: fileURL(for: userID), options: [.atomic])
    }

    private func fileURL(for userID: String) -> URL {
        rootURL.appendingPathComponent(fileName(for: userID), isDirectory: false)
    }

    private func fileName(for userID: String) -> String {
        userID.utf8.map { String(format: "%02x", $0) }.joined() + ".json"
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

private struct CircleFeedTopLoadingView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.78)

            Text("正在刷新")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在更新内容")
    }
}

private struct CirclePublishStatusToast: View {
    enum StateStyle: Equatable {
        case posting
        case succeeded
        case failed(String)
    }

    let state: StateStyle

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 42, height: 42)

                if showsSpinner {
                    ProgressView()
                        .tint(tint)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(tint)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                }

                ProgressView(value: progress)
                    .tint(tint)
                    .scaleEffect(x: 1, y: 0.72, anchor: .center)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.14), radius: 22, x: 0, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(subtitle)")
    }

    private var title: String {
        switch state {
        case .posting:
            return "正在发布作品"
        case .succeeded:
            return "发布成功"
        case .failed:
            return "发布失败"
        }
    }

    private var subtitle: String {
        switch state {
        case .posting:
            return "照片正在上传，请稍等"
        case .succeeded:
            return "已提交到圈子，列表将自动更新"
        case .failed(let message):
            return message
        }
    }

    private var progress: Double {
        switch state {
        case .posting:
            return 0.42
        case .succeeded:
            return 1
        case .failed:
            return 1
        }
    }

    private var showsSpinner: Bool {
        state == .posting
    }

    private var iconName: String {
        switch state {
        case .posting:
            return "arrow.up.circle.fill"
        case .succeeded:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .posting:
            return Color(red: 0.86, green: 0.16, blue: 0.22)
        case .succeeded:
            return .green
        case .failed:
            return .red
        }
    }
}

private struct CircleTransferStatusToast: View {
    enum StateStyle {
        case preparing
        case transferring
        case succeeded
        case failed
    }

    let state: StateStyle
    let title: String
    let subtitle: String
    let progress: Double

    private var clampedProgress: CGFloat {
        CGFloat(min(1, max(0, progress)))
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 42, height: 42)

                if state == .preparing {
                    ProgressView()
                        .tint(tint)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(tint)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    if showsPercent {
                        Text("\(Int((clampedProgress * 100).rounded()))%")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(tint)
                            .monospacedDigit()
                    }
                }

                ProgressView(value: Double(clampedProgress))
                    .tint(tint)
                    .scaleEffect(x: 1, y: 0.72, anchor: .center)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.14), radius: 22, x: 0, y: 10)
    }

    private var showsPercent: Bool {
        state == .preparing || state == .transferring
    }

    private var iconName: String {
        switch state {
        case .preparing:
            return "arrow.down.circle.fill"
        case .transferring:
            return "paperplane.fill"
        case .succeeded:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .preparing, .transferring:
            return Color(red: 0.86, green: 0.16, blue: 0.22)
        case .succeeded:
            return .green
        case .failed:
            return .red
        }
    }
}
