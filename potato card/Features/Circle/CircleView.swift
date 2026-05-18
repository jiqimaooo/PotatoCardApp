import SwiftUI
import UIKit

struct CircleView: View {
    @EnvironmentObject private var bleService: BleTransferService
    @StateObject private var sessionStore = CircleSessionStore()
    @State private var posts: [CirclePost] = []
    @State private var isComposerPresented = false
    @State private var isDriftBottleThrowPresented = false
    @State private var isLoadingPosts = false
    @State private var hasCompletedInitialPostsLoad = false
    @State private var transferStatusVisibilityTask: Task<Void, Never>?
    @State private var isTransferStatusVisible = false
    @State private var toastMessage: CircleToastMessage?
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var publishStatusVisibilityTask: Task<Void, Never>?
    @State private var publishStatusState: CirclePublishStatusToast.StateStyle = .posting
    @State private var isPublishStatusVisible = false
    @State private var selectedFeedSection: FeedSection = .discover
    @State private var viewedPostIDs: Set<String> = []
    @State private var isHeaderHidden = false
    @State private var lastFeedScrollOffset: CGFloat = 0
    @State private var circleImageViewerRequest: CircleImageViewerRequest?
    @State private var isPreparingTransferSheet = false

    private let apiClient: CircleAPIClient
    private let bottomFloatingContentPadding = AppBottomBarMetrics.floatingControlBottomPadding

    private enum FeedSection: CaseIterable, Hashable {
        case discover
        case following
        case latest
        case driftBottle

        var title: String {
            switch self {
            case .discover:
                return "发现"
            case .following:
                return "关注"
            case .latest:
                return "最新"
            case .driftBottle:
                return "漂流瓶"
            }
        }

        var index: Int {
            Self.allCases.firstIndex(of: self) ?? 0
        }
    }

    private var sessionAPIClient: CircleAPIClient {
        var client = apiClient
        client.tokenProvider = { sessionStore.token }
        return client
    }

    init(apiClient: CircleAPIClient = CircleView.defaultAPIClient()) {
        self.apiClient = apiClient
    }

    var body: some View {
        Group {
            if sessionStore.isRegistered {
                ZStack(alignment: .bottom) {
                    if selectedFeedSection == .driftBottle {
                        CircleDriftBottleOceanBackdrop()
                            .ignoresSafeArea()
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        if !isHeaderHidden {
                            header
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        feedContent
                    }

                    if shouldShowBottomPublishButton {
                        bottomPublishButton
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
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
                    .padding(.bottom, bottomFloatingContentPadding)
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isTransferStatusVisible)
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: toastMessage)
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isPublishStatusVisible)
                .animation(.spring(response: 0.30, dampingFraction: 0.88), value: isHeaderHidden)
                .animation(.easeInOut(duration: 0.18), value: isLoadingPosts)
            } else {
                CircleRegistrationView(sessionStore: sessionStore, apiClient: apiClient)
            }
        }
        .onAppear {
            sessionStore.loadFromStorage()
            loadViewedPostIDs()
            loadPostsIfNeeded()
        }
        .onChange(of: sessionStore.isRegistered) { isRegistered in
            guard isRegistered else { return }
            loadViewedPostIDs()
            loadPostsIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: CircleSessionStore.didSignOutNotification)) { _ in
            posts = []
            toastMessage = nil
            isPublishStatusVisible = false
            isComposerPresented = false
            isDriftBottleThrowPresented = false
            hasCompletedInitialPostsLoad = false
            selectedFeedSection = .discover
            viewedPostIDs = []
            resetFeedHeaderVisibility()
            sessionStore.loadFromStorage()
        }
        .onChange(of: bleService.transferPhase) { phase in
            handleTransferPhaseChange(phase)
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
        .sheet(isPresented: $isDriftBottleThrowPresented) {
            CircleDriftBottleThrowComposerView { imageData in
                publishDriftBottle(imageData: imageData)
            }
        }
        .sheet(item: $circleImageViewerRequest) { request in
            GalleryImageViewer(
                photos: [request.photo],
                initialIndex: 0,
                onTransferToDevice: { _ in },
                editStateKeyForPhoto: { _ in .circle(request.post.id) },
                transferImageProvider: { _ in
                    let image = try await fetchTransferImageWithRefresh(for: request.post)
                    return GalleryPreparedTransferImage(
                        imageData: encodedImageData(for: image),
                        image: image
                    )
                },
                isContentLocked: true,
                lockedPreviewText: request.lockedPreviewText,
                transferButtonTitle: "传输到设备解锁原图"
            )
            .presentationDetents([.height(560)])
            .presentationDragIndicator(.visible)
            .environmentObject(bleService)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ForEach(FeedSection.allCases, id: \.self) { section in
                feedTab(section)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(headerBackgroundColor)
    }

    private var headerBackgroundColor: Color {
        selectedFeedSection == .driftBottle ? .clear : Color(.systemBackground)
    }

    private func feedTab(_ section: FeedSection) -> some View {
        Button {
            selectFeedSection(section)
        } label: {
            CircleFeedTab(title: section.title, isSelected: selectedFeedSection == section)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
    }

    @ViewBuilder
    private var feedContent: some View {
        if showsFullPageLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack(alignment: .top) {
                feedPager

                if shouldShowTopLoading {
                    CircleFeedTopLoadingView()
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    @ViewBuilder
    private var feedPager: some View {
        feedPageContent(for: selectedFeedSection)
            .id(selectedFeedSection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(feedSectionSwipeGesture)
            .onChange(of: selectedFeedSection) { section in
                handleSelectedFeedSectionChange(section)
            }
    }

    @ViewBuilder
    private func feedPageContent(for section: FeedSection) -> some View {
        switch section {
        case .discover:
            CircleFeedView(
                posts: posts,
                viewedPostIDs: viewedPostIDs,
                isImageLoadingEnabled: selectedFeedSection == section,
                onTransfer: openTransferSheet,
                onReport: handleReport,
                onRefresh: refreshPosts,
                onScrollOffsetChange: handleFeedScrollOffset
            )
        case .following:
            CircleUnavailableFeedView(title: "关注")
        case .latest:
            CircleFeedView(
                posts: latestPosts,
                viewedPostIDs: viewedPostIDs,
                isImageLoadingEnabled: selectedFeedSection == section,
                onTransfer: openTransferSheet,
                onReport: handleReport,
                onRefresh: refreshPosts,
                onScrollOffsetChange: handleFeedScrollOffset
            )
        case .driftBottle:
            CircleDriftBottleView(
                posts: posts,
                onTransfer: openDriftBottleTransferSheet,
                onThrow: {
                    isDriftBottleThrowPresented = true
                },
                onRefresh: refreshPosts,
                onScrollOffsetChange: handleFeedScrollOffset
            )
        }
    }

    private func handleSelectedFeedSectionChange(_ section: FeedSection) {
        resetFeedHeaderVisibility()
    }

    private var feedSectionSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28, coordinateSpace: .local)
            .onEnded { value in
                let horizontalDistance = value.translation.width
                let verticalDistance = value.translation.height
                guard abs(horizontalDistance) > 54 else { return }
                guard abs(horizontalDistance) > abs(verticalDistance) * 1.2 else { return }

                if horizontalDistance < 0 {
                    selectAdjacentFeedSection(offset: 1)
                } else {
                    selectAdjacentFeedSection(offset: -1)
                }
            }
    }

    private func selectAdjacentFeedSection(offset: Int) {
        let nextIndex = selectedFeedSection.index + offset
        guard FeedSection.allCases.indices.contains(nextIndex) else { return }
        selectFeedSection(FeedSection.allCases[nextIndex])
    }

    private func selectFeedSection(_ section: FeedSection) {
        guard selectedFeedSection != section else { return }
        withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
            selectedFeedSection = section
        }
    }

    private var latestPosts: [CirclePost] {
        posts.sorted { $0.createdAt > $1.createdAt }
    }

    private var shouldShowBottomPublishButton: Bool {
        selectedFeedSection == .discover || selectedFeedSection == .latest
    }

    private var bottomPublishButton: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                Button {
                    isComposerPresented = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Color(red: 0.86, green: 0.16, blue: 0.22), in: Circle())
                        .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("发布作品")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, bottomFloatingContentPadding)
        }
        .allowsHitTesting(true)
    }

    private func handleFeedScrollOffset(_ offset: CGFloat) {
        if offset > -12 {
            setHeaderHidden(false)
        } else if offset < -34 {
            setHeaderHidden(true)
        }

        lastFeedScrollOffset = offset
    }

    private func resetFeedHeaderVisibility() {
        lastFeedScrollOffset = 0
        setHeaderHidden(false)
    }

    private func setHeaderHidden(_ hidden: Bool) {
        guard isHeaderHidden != hidden else { return }
        isHeaderHidden = hidden
    }

    private var transferStatusState: CircleTransferStatusToast.StateStyle {
        if isPreparingTransferSheet { return .preparing }
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
        if isPreparingTransferSheet { return "正在获取圈子图片" }
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
        if isPreparingTransferSheet { return "马上打开传输面板" }
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
        if isPreparingTransferSheet { return 0.08 }
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

    private var shouldShowTopLoading: Bool {
        isLoadingPosts && hasCompletedInitialPostsLoad
    }

    private var isTransferBusy: Bool {
        isPreparingTransferSheet ||
        bleService.transferPhase == .preparing ||
        bleService.transferPhase == .transferring
    }

    private func openTransferSheet(_ post: CirclePost) {
        markPostViewed(post)
        presentTransferSheet(
            for: post,
            previewImage: lockedTransferPreviewImage(for: post),
            title: post.title,
            lockedPreviewText: "点击传输以查看"
        )
    }

    private func openDriftBottleTransferSheet(_ post: CirclePost) {
        markPostViewed(post)
        presentTransferSheet(
            for: post,
            previewImage: blankLockedTransferPreviewImage(for: post),
            title: "漂流瓶",
            lockedPreviewText: "传输后才能查看"
        )
    }

    private func presentTransferSheet(
        for post: CirclePost,
        previewImage: UIImage,
        title: String,
        lockedPreviewText: String
    ) {
        guard !isTransferBusy else {
            showToast(BleTransferError.transferBusy.localizedDescription, style: .error)
            return
        }
        circleImageViewerRequest = CircleImageViewerRequest(
            post: post,
            photo: GalleryPhoto(
                id: UUID(),
                imageData: encodedImageData(for: previewImage),
                image: previewImage,
                title: title
            ),
            lockedPreviewText: lockedPreviewText
        )
    }

    private func lockedTransferPreviewImage(for post: CirclePost) -> UIImage {
        let imageSize = CGSize(
            width: max(360, post.previewWidth ?? post.targetWidth ?? 720),
            height: max(520, post.previewHeight ?? post.targetHeight ?? 1080)
        )
        let colors = lockedPreviewColors(for: post.id + post.title)
        let renderer = UIGraphicsImageRenderer(size: imageSize)

        return renderer.image { context in
            let cgContext = context.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let cgColors = colors.map(\.cgColor) as CFArray
            let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: [0, 0.58, 1])

            cgContext.drawLinearGradient(
                gradient!,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: imageSize.width, y: imageSize.height),
                options: []
            )

            UIColor.white.withAlphaComponent(0.10).setFill()
            for index in 0..<5 {
                let diameter = imageSize.width * CGFloat(0.24 + Double(index) * 0.07)
                let origin = CGPoint(
                    x: imageSize.width * CGFloat(0.12 + Double(index % 3) * 0.28),
                    y: imageSize.height * CGFloat(0.14 + Double(index) * 0.13)
                )
                cgContext.fillEllipse(in: CGRect(origin: origin, size: CGSize(width: diameter, height: diameter)))
            }
        }
    }

    private func blankLockedTransferPreviewImage(for post: CirclePost) -> UIImage {
        let imageSize = CGSize(
            width: max(360, post.targetWidth ?? post.previewWidth ?? 720),
            height: max(520, post.targetHeight ?? post.previewHeight ?? 1080)
        )
        let renderer = UIGraphicsImageRenderer(size: imageSize)

        return renderer.image { context in
            UIColor(red: 0.36, green: 0.39, blue: 0.42, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: imageSize))
        }
    }

    private func lockedPreviewColors(for seedText: String) -> [UIColor] {
        let palettes: [[UIColor]] = [
            [UIColor(red: 0.20, green: 0.29, blue: 0.36, alpha: 1), UIColor(red: 0.43, green: 0.48, blue: 0.57, alpha: 1), UIColor(red: 0.12, green: 0.18, blue: 0.24, alpha: 1)],
            [UIColor(red: 0.34, green: 0.25, blue: 0.27, alpha: 1), UIColor(red: 0.58, green: 0.49, blue: 0.48, alpha: 1), UIColor(red: 0.18, green: 0.20, blue: 0.24, alpha: 1)],
            [UIColor(red: 0.18, green: 0.31, blue: 0.39, alpha: 1), UIColor(red: 0.46, green: 0.58, blue: 0.66, alpha: 1), UIColor(red: 0.14, green: 0.22, blue: 0.28, alpha: 1)],
            [UIColor(red: 0.42, green: 0.36, blue: 0.30, alpha: 1), UIColor(red: 0.62, green: 0.57, blue: 0.48, alpha: 1), UIColor(red: 0.22, green: 0.20, blue: 0.18, alpha: 1)]
        ]
        var hash: UInt32 = 2_166_136_261
        for scalar in seedText.unicodeScalars {
            hash = (hash ^ UInt32(scalar.value)) &* 16_777_619
        }
        return palettes[Int(hash) % palettes.count]
    }

    private func encodedImageData(for image: UIImage) -> Data {
        image.jpegData(compressionQuality: 0.95) ?? image.pngData() ?? Data()
    }

    private func handleReport(_ post: CirclePost) {
        showToast("已提交举报：\(post.title)", style: .success)
    }

    private func loadViewedPostIDs() {
        guard let userID = sessionStore.profile?.id else {
            viewedPostIDs = []
            return
        }
        viewedPostIDs = CircleViewedPostStore.shared.loadViewedPostIDs(for: userID)
    }

    private func markPostViewed(_ post: CirclePost) {
        guard let userID = sessionStore.profile?.id else { return }
        guard !viewedPostIDs.contains(post.id) else { return }
        viewedPostIDs.insert(post.id)
        CircleViewedPostStore.shared.saveViewedPostIDs(viewedPostIDs, for: userID)
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
            hasCompletedInitialPostsLoad = true
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

    private func publishDriftBottle(imageData: Data) {
        publish(imageData: imageData, title: "漂流瓶", tags: [])
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

    private func fetchTransferImageWithRefresh(for post: CirclePost) async throws -> UIImage {
        let accessToken = try await validAccessToken()
        do {
            return try await fetchTransferImage(for: post, accessToken: accessToken)
        } catch CircleAPIError.unauthorized {
            let refreshedToken = try await validAccessToken(forceRefresh: true)
            return try await fetchTransferImage(for: post, accessToken: refreshedToken)
        }
    }

    private func fetchTransferImage(for post: CirclePost, accessToken: String) async throws -> UIImage {
        let ticket = try await sessionAPIClient.transferTicket(postID: post.id, accessToken: accessToken)
        return try await sessionAPIClient.downloadTransferImage(from: ticket.downloadUrl)
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

private struct CircleImageViewerRequest: Identifiable {
    let id = UUID()
    let post: CirclePost
    let photo: GalleryPhoto
    let lockedPreviewText: String
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
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
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
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
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

private final class CircleViewedPostStore {
    static let shared = CircleViewedPostStore()

    private let defaults = UserDefaults.standard
    private let maxStoredCount = 2_000

    private init() {}

    func loadViewedPostIDs(for userID: String) -> Set<String> {
        Set(defaults.stringArray(forKey: key(for: userID)) ?? [])
    }

    func saveViewedPostIDs(_ ids: Set<String>, for userID: String) {
        defaults.set(Array(ids.prefix(maxStoredCount)), forKey: key(for: userID))
    }

    private func key(for userID: String) -> String {
        "CircleViewedPostIDs.\(userID)"
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
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
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
