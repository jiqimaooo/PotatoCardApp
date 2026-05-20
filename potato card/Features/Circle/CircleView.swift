import PhotosUI
import SwiftUI
import UIKit

struct CircleView: View {
    @EnvironmentObject private var bleService: BleTransferService
    @StateObject private var sessionStore = CircleSessionStore()
    @State private var posts: [CirclePost] = []
    @State private var isComposerPresented = false
    @State private var isDriftBottleThrowPresented = false
    @State private var isLoadingPosts = false
    @State private var isLoadingMorePosts = false
    @State private var nextPostsCursor: String?
    @State private var hasMorePosts = false
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
    @State private var driftBottlePost: CirclePost?
    @State private var isDrawingDriftBottle = false
    @State private var driftBottleRemainingDraws: Int?
    @State private var driftBottleDailyLimit: Int?
    @State private var isHeaderHidden = false
    @State private var lastFeedScrollOffset: CGFloat = 0
    @State private var circleImageViewerRequest: CircleImageViewerRequest?
    @State private var isPreparingTransferSheet = false
    @State private var isBetaNoticePresented = false

    private let apiClient: CircleAPIClient
    private let bottomFloatingContentPadding = AppBottomBarMetrics.floatingControlBottomPadding

    private enum FeedSection: CaseIterable, Hashable {
        case discover
        case following
        case latest
        case driftBottle
        case imageToken

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
            case .imageToken:
                return "口令传图"
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
            isLoadingPosts = false
            isLoadingMorePosts = false
            nextPostsCursor = nil
            hasMorePosts = false
            toastMessage = nil
            isPublishStatusVisible = false
            isComposerPresented = false
            isDriftBottleThrowPresented = false
            driftBottlePost = nil
            isDrawingDriftBottle = false
            driftBottleRemainingDraws = nil
            driftBottleDailyLimit = nil
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
        .sheet(isPresented: $isBetaNoticePresented) {
            CircleBetaNoticeSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(FeedSection.allCases, id: \.self) { section in
                        feedTab(section)
                    }
                }
                .padding(.trailing, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
            betaBadge
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

    private var betaBadge: some View {
        Button {
            isBetaNoticePresented = true
        } label: {
            Text("BETA")
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(.systemBackground), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.primary.opacity(0.22), lineWidth: 0.8)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("土豆圈 Beta 试运行说明")
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
                hasMorePosts: hasMorePosts,
                isLoadingMorePosts: isLoadingMorePosts,
                onTransfer: openTransferSheet,
                onReport: handleReport,
                onRefresh: refreshPosts,
                onLoadMore: loadMorePostsIfNeeded,
                onScrollOffsetChange: handleFeedScrollOffset
            )
        case .following:
            CircleUnavailableFeedView(title: "关注")
        case .latest:
            CircleFeedView(
                posts: latestPosts,
                viewedPostIDs: viewedPostIDs,
                isImageLoadingEnabled: selectedFeedSection == section,
                hasMorePosts: hasMorePosts,
                isLoadingMorePosts: isLoadingMorePosts,
                onTransfer: openTransferSheet,
                onReport: handleReport,
                onRefresh: refreshPosts,
                onLoadMore: loadMorePostsIfNeeded,
                onScrollOffsetChange: handleFeedScrollOffset
            )
        case .driftBottle:
            CircleDriftBottleView(
                post: driftBottlePost,
                isDrawing: isDrawingDriftBottle,
                remainingDrawCount: driftBottleRemainingDraws,
                dailyDrawLimit: driftBottleDailyLimit,
                onTransfer: openDriftBottleTransferSheet,
                onThrow: {
                    isDriftBottleThrowPresented = true
                },
                onDraw: drawDriftBottle,
                onScrollOffsetChange: handleFeedScrollOffset
            )
        case .imageToken:
            CircleImageTokenTransferView(
                apiClient: sessionAPIClient,
                accessTokenProvider: { forceRefresh in
                    try await validAccessToken(forceRefresh: forceRefresh)
                },
                onSessionError: handleSessionError,
                onToast: showToast
            )
            .environmentObject(bleService)
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
        isLoadingMorePosts = false
        Task {
            do {
                let page = try await fetchPostsWithRefresh(cursor: nil)
                posts = page.items
                nextPostsCursor = page.nextCursor
                hasMorePosts = page.hasMore
                saveCachedPosts(page.items)
                syncCurrentProfileAvatar(from: page.items)
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
                    let page = try await fetchPostsWithRefresh(cursor: nil)
                    posts = page.items
                    nextPostsCursor = page.nextCursor
                    hasMorePosts = page.hasMore
                    saveCachedPosts(page.items)
                    syncCurrentProfileAvatar(from: page.items)
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
        showPublishStatus(.posting)
        Task {
            do {
                try await createDriftBottleWithRefresh(imageData: imageData)
                showPublishStatus(.succeeded)
                showToast("漂流瓶已扔进海里", style: .success)
                hidePublishStatus(after: 2)
            } catch {
                showPublishStatus(.failed(error.localizedDescription))
                hidePublishStatus(after: 3)
                handleSessionError(error)
            }
        }
    }

    private func fetchPostsWithRefresh(cursor: String?) async throws -> CircleFeedResponse {
        _ = try await validAccessToken()
        do {
            return try await sessionAPIClient.fetchPosts(cursor: cursor)
        } catch CircleAPIError.unauthorized {
            _ = try await validAccessToken(forceRefresh: true)
            return try await sessionAPIClient.fetchPosts(cursor: cursor)
        }
    }

    private func loadMorePostsIfNeeded() {
        guard !isLoadingPosts, !isLoadingMorePosts, hasMorePosts, let cursor = nextPostsCursor else { return }
        isLoadingMorePosts = true

        Task {
            do {
                let page = try await fetchPostsWithRefresh(cursor: cursor)
                appendPosts(page.items)
                nextPostsCursor = page.nextCursor
                hasMorePosts = page.hasMore
                saveCachedPosts(posts)
                syncCurrentProfileAvatar(from: page.items)
            } catch {
                handleSessionError(error)
            }
            isLoadingMorePosts = false
        }
    }

    private func appendPosts(_ pagePosts: [CirclePost]) {
        let existingIDs = Set(posts.map(\.id))
        posts.append(contentsOf: pagePosts.filter { !existingIDs.contains($0.id) })
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

    private func createDriftBottleWithRefresh(imageData: Data) async throws {
        let accessToken = try await validAccessToken()
        do {
            try await sessionAPIClient.createDriftBottle(imageData: imageData, accessToken: accessToken)
        } catch CircleAPIError.unauthorized {
            let refreshedToken = try await validAccessToken(forceRefresh: true)
            try await sessionAPIClient.createDriftBottle(imageData: imageData, accessToken: refreshedToken)
        }
    }

    private func drawDriftBottle() {
        guard !isDrawingDriftBottle else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
            isDrawingDriftBottle = true
        }

        Task {
            do {
                let response = try await drawDriftBottleWithRefresh()
                driftBottleRemainingDraws = response.remainingDraws
                driftBottleDailyLimit = response.dailyLimit

                if let item = response.item {
                    withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) {
                        driftBottlePost = item
                    }
                } else {
                    switch response.reason {
                    case "LIMIT_REACHED":
                        showToast("今天的漂流瓶已经捞完了", style: .error)
                    default:
                        showToast("海面暂时没有可打捞的漂流瓶", style: .error)
                    }
                }
            } catch {
                handleSessionError(error)
            }

            withAnimation(.easeOut(duration: 0.24)) {
                isDrawingDriftBottle = false
            }
        }
    }

    private func drawDriftBottleWithRefresh() async throws -> CircleDriftBottleDrawResponse {
        let accessToken = try await validAccessToken()
        do {
            return try await sessionAPIClient.drawDriftBottle(accessToken: accessToken)
        } catch CircleAPIError.unauthorized {
            let refreshedToken = try await validAccessToken(forceRefresh: true)
            return try await sessionAPIClient.drawDriftBottle(accessToken: refreshedToken)
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
        syncCurrentProfileAvatar(from: cachedPosts)
    }

    private func saveCachedPosts(_ posts: [CirclePost]) {
        guard let userID = sessionStore.profile?.id else { return }
        CircleFeedPostCache.shared.savePosts(posts, for: userID)
    }

    private func syncCurrentProfileAvatar(from posts: [CirclePost]) {
        guard
            let profile = sessionStore.profile,
            profile.avatarUrl == nil,
            let avatarUrl = posts.first(where: { $0.author.id == profile.id })?.author.avatarUrl
        else {
            return
        }
        sessionStore.updateProfileAvatarURL(avatarUrl)
    }

    private func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        try await sessionStore.validAccessToken(using: apiClient, forceRefresh: forceRefresh)
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

private struct CircleImageTokenTransferView: View {
    enum Mode: String, CaseIterable {
        case send = "发送"
        case receive = "接收"
    }

    let apiClient: CircleAPIClient
    let accessTokenProvider: (Bool) async throws -> String
    let onSessionError: (Error) -> Void
    let onToast: (String, CircleToastMessage.Style) -> Void

    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.colorScheme) private var colorScheme
    @State private var mode: Mode = .send
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var selectedImageData: Data?
    @State private var customTokenCode = ""
    @State private var isBurnAfterRead = true
    @State private var expiresInHours = 24
    @State private var createdToken: CircleImageToken?
    @State private var claimCode = ""
    @State private var receivedTokens: [CircleImageToken] = []
    @State private var isCreating = false
    @State private var isClaiming = false
    @State private var isLoadingReceived = false
    @State private var isPreparingTokenTransfer = false
    @State private var pendingTransferToken: CircleImageToken?
    @State private var transientReceivedTokenIDs: Set<String> = []
    @State private var receivedTokenDismissalIDs: [String: UUID] = [:]

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    modePicker

                    if mode == .send {
                        sendSection
                    } else {
                        receiveSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, AppBottomBarMetrics.scrollContentBottomPadding)
                .frame(width: proxy.size.width, alignment: .leading)
            }
        }
        .background(Color(.systemGroupedBackground))
        .task {
            await loadReceivedTokens()
        }
        .onChange(of: selectedPhotoItem) { item in
            loadSelectedPhoto(item)
        }
        .onChange(of: bleService.transferPhase) { phase in
            handleTransferPhaseChange(phase)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("口令传图")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)
            Text("领取后不能在手机查看，只能传输到土豆片设备。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modePicker: some View {
        Picker("口令传图模式", selection: $mode) {
            ForEach(Mode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var sendSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            imageTokenPhotoPicker

            VStack(spacing: 0) {
                settingsRow(icon: "textformat.123", title: "口令") {
                    TextField("留空自动生成", text: $customTokenCode)
                        .font(.system(size: 15, weight: .semibold))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                Divider().padding(.leading, 44)

                settingsRow(icon: "flame", title: "阅后即焚") {
                    Toggle("", isOn: $isBurnAfterRead)
                        .labelsHidden()
                        .tint(Color(red: 0.86, green: 0.16, blue: 0.22))
                }

                Divider().padding(.leading, 44)

                settingsRow(icon: "clock", title: "有效期") {
                    Stepper("\(expiresInHours) 小时", value: $expiresInHours, in: 1...168, step: 1)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(cardStrokeColor, lineWidth: 1)
            }

            Button {
                createToken()
            } label: {
                HStack(spacing: 8) {
                    if isCreating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "key.fill")
                    }
                    Text(isCreating ? "正在生成" : "生成口令")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(createButtonEnabled ? Color(red: 0.86, green: 0.16, blue: 0.22) : Color(.systemGray3), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!createButtonEnabled)

            if let createdToken {
                createdTokenCard(createdToken)
            }
        }
    }

    private var imageTokenPhotoPicker: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))

                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: width, height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(Color(red: 0.86, green: 0.16, blue: 0.22))
                            Text("选择要生成口令的图片")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("发送方可预览，接收方不可在手机查看")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: width, height: 210)
                    }
                }
                .frame(width: width, height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(cardStrokeColor, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: width, height: 210)
            .clipped()
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 210)
    }

    private var receiveSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                settingsRow(icon: "keyboard", title: "输入口令") {
                    TextField("例如 POTATO24", text: $claimCode)
                        .font(.system(size: 15, weight: .semibold))
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(cardStrokeColor, lineWidth: 1)
            }

            Button {
                claimToken()
            } label: {
                HStack(spacing: 8) {
                    if isClaiming {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "tray.and.arrow.down.fill")
                    }
                    Text(isClaiming ? "正在领取" : "领取图片")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(claimButtonEnabled ? Color(red: 0.86, green: 0.16, blue: 0.22) : Color(.systemGray3), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!claimButtonEnabled)

            if isLoadingReceived {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if visibleReceivedTokens.isEmpty {
                emptyLockedState
            } else {
                VStack(spacing: 12) {
                    ForEach(visibleReceivedTokens) { token in
                        lockedTokenCard(token)
                    }
                }
            }
        }
    }

    private var visibleReceivedTokens: [CircleImageToken] {
        receivedTokens.filter { token in
            token.status == .claimed || transientReceivedTokenIDs.contains(token.id)
        }
    }

    private var emptyLockedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.rectangle.stack")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color(red: 0.86, green: 0.16, blue: 0.22))
            Text("还没有领取图片")
                .font(.system(size: 17, weight: .bold))
            Text("输入口令后，图片会以锁定状态进入待传输列表。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        }
    }

    private func createdTokenCard(_ token: CircleImageToken) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("口令已生成")
                .font(.system(size: 15, weight: .bold))
            HStack(spacing: 10) {
                Text(token.tokenCode)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.86, green: 0.16, blue: 0.22))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Button {
                    UIPasteboard.general.string = token.tokenCode
                    onToast("口令已复制", .success)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.plain)
            }
            Text("发送给对方后，对方领取成功即失效。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        }
    }

    private func lockedTokenCard(_ token: CircleImageToken) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.86, green: 0.16, blue: 0.22).opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: token.status == .destroyed ? "checkmark.seal.fill" : "lock.display")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(Color(red: 0.86, green: 0.16, blue: 0.22))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(token.status == .destroyed ? "图片已传输并销毁" : "图片已接收")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(token.status == .claimed ? "请传输到土豆片后查看" : token.statusText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if token.status == .claimed {
                Button {
                    beginTransfer(token)
                } label: {
                    HStack(spacing: 8) {
                        if isPreparingTokenTransfer && pendingTransferToken?.id == token.id {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(isPreparingTokenTransfer && pendingTransferToken?.id == token.id ? "正在准备传输" : "传输到土豆片")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color(red: 0.86, green: 0.16, blue: 0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isPreparingTokenTransfer)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        }
    }

    private func settingsRow<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.86, green: 0.16, blue: 0.22))
                .frame(width: 32, height: 32)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 10)
            content()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 54)
    }

    private var cardStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)
    }

    private var createButtonEnabled: Bool {
        selectedImageData != nil && !isCreating
    }

    private var claimButtonEnabled: Bool {
        !claimCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isClaiming
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let jpegData = image.jpegData(compressionQuality: 0.86) else {
                    onToast("图片读取失败", .error)
                    return
                }
                await MainActor.run {
                    selectedImage = image
                    selectedImageData = jpegData
                    selectedPhotoItem = nil
                    createdToken = nil
                }
            } catch {
                await MainActor.run {
                    onToast(error.localizedDescription, .error)
                }
            }
        }
    }

    private func createToken() {
        guard let selectedImageData else { return }
        isCreating = true
        Task {
            do {
                let token = try await performAuthenticated { accessToken in
                    try await apiClient.createImageToken(
                        imageData: selectedImageData,
                        tokenCode: customTokenCode,
                        isBurnAfterRead: isBurnAfterRead,
                        expiresInHours: expiresInHours,
                        accessToken: accessToken
                    )
                }
                await MainActor.run {
                    createdToken = token
                    customTokenCode = ""
                    onToast("口令已生成", .success)
                }
            } catch {
                await MainActor.run {
                    onSessionError(error)
                }
            }
            await MainActor.run {
                isCreating = false
            }
        }
    }

    private func claimToken() {
        let code = claimCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        isClaiming = true
        Task {
            do {
                let token = try await performAuthenticated { accessToken in
                    try await apiClient.claimImageToken(tokenCode: code, accessToken: accessToken)
                }
                await MainActor.run {
                    upsertReceivedToken(token)
                    claimCode = ""
                    onToast("图片已接收，请传输到土豆片后查看", .success)
                }
            } catch {
                await MainActor.run {
                    onSessionError(error)
                }
            }
            await MainActor.run {
                isClaiming = false
            }
        }
    }

    private func loadReceivedTokens() async {
        isLoadingReceived = true
        defer { isLoadingReceived = false }
        do {
            receivedTokens = try await performAuthenticated { accessToken in
                try await apiClient.fetchReceivedImageTokens(accessToken: accessToken)
            }
        } catch {
            onSessionError(error)
        }
    }

    private func beginTransfer(_ token: CircleImageToken) {
        guard !isPreparingTokenTransfer else { return }
        guard bleService.transferPhase != .preparing && bleService.transferPhase != .transferring else {
            onToast(BleTransferError.transferBusy.localizedDescription, .error)
            return
        }
        guard let device = bleService.connectedDevice ?? bleService.selectedDevice else {
            onToast("请先连接土豆片设备", .error)
            return
        }

        pendingTransferToken = token
        isPreparingTokenTransfer = true
        Task {
            do {
                let image = try await performAuthenticated { accessToken in
                    try await apiClient.downloadImageTokenTransferImage(id: token.id, accessToken: accessToken)
                }
                let displayImage = EInkImageRenderer.render(
                    image: image,
                    targetSize: device.profile.pixelSize,
                    fitMode: .centerCrop,
                    adjustment: .default
                )
                let transferImage = EInkImageRenderer.renderForTransfer(
                    image: image,
                    targetSize: device.profile.pixelSize,
                    fitMode: .centerCrop,
                    adjustment: .default,
                    profile: device.profile,
                    ditherAlgorithm: bleService.ditherAlgorithm
                )
                await MainActor.run {
                    bleService.transfer(image: transferImage, displayImage: displayImage, to: device)
                }
            } catch {
                await MainActor.run {
                    pendingTransferToken = nil
                    onSessionError(error)
                }
            }
            await MainActor.run {
                isPreparingTokenTransfer = false
            }
        }
    }

    private func handleTransferPhaseChange(_ phase: TransferPhase) {
        switch phase {
        case .succeeded:
            guard let pendingTransferToken else { return }
            let deviceID = bleService.connectedDevice?.id ?? bleService.selectedDevice?.id
            Task {
                do {
                    let updated = try await performAuthenticated { accessToken in
                        try await apiClient.recordImageTokenTransfer(
                            id: pendingTransferToken.id,
                            deviceID: deviceID,
                            accessToken: accessToken
                        )
                    }
                    await MainActor.run {
                        upsertReceivedToken(updated)
                        self.pendingTransferToken = nil
                        onToast(updated.isBurnAfterRead ? "图片已传输并销毁" : "图片已传输", .success)
                    }
                } catch {
                    await MainActor.run {
                        self.pendingTransferToken = nil
                        onSessionError(error)
                    }
                }
            }
        case .failed:
            pendingTransferToken = nil
        case .idle, .preparing, .transferring:
            break
        }
    }

    private func upsertReceivedToken(_ token: CircleImageToken) {
        if let index = receivedTokens.firstIndex(where: { $0.id == token.id }) {
            receivedTokens[index] = token
        } else {
            receivedTokens.insert(token, at: 0)
        }

        if token.status == .transferred || token.status == .destroyed {
            scheduleReceivedTokenDismissal(token.id)
        }
    }

    private func scheduleReceivedTokenDismissal(_ tokenID: String) {
        let dismissalID = UUID()
        transientReceivedTokenIDs.insert(tokenID)
        receivedTokenDismissalIDs[tokenID] = dismissalID

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                guard receivedTokenDismissalIDs[tokenID] == dismissalID else { return }
                receivedTokenDismissalIDs[tokenID] = nil

                withAnimation(.easeInOut(duration: 0.22)) {
                    transientReceivedTokenIDs.remove(tokenID)
                    if let index = receivedTokens.firstIndex(where: { $0.id == tokenID }),
                       receivedTokens[index].status != .claimed {
                        receivedTokens.remove(at: index)
                    }
                }
            }
        }
    }

    private func performAuthenticated<T>(_ operation: (String) async throws -> T) async throws -> T {
        let accessToken = try await accessTokenProvider(false)
        do {
            return try await operation(accessToken)
        } catch CircleAPIError.unauthorized {
            let refreshedToken = try await accessTokenProvider(true)
            return try await operation(refreshedToken)
        }
    }
}

private extension CircleImageToken {
    var statusText: String {
        switch status {
        case .active:
            return "未领取"
        case .claimed:
            return "请传输到土豆片后查看"
        case .expired:
            return "该口令已过期"
        case .transferred:
            return "图片已传输，服务端图片已销毁"
        case .destroyed:
            return "图片已传输并销毁"
        }
    }
}

private struct CircleBetaNoticeSheet: View {
    private let riskItems = [
        "服务不稳定",
        "功能变更",
        "数据结构调整",
        "临时停服或重置",
    ]

    private let dataItems = [
        "用户名与头像",
        "发布内容",
        "评论与点赞",
        "收藏记录",
        "圈子身份信息",
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    paragraph("土豆圈目前仍处于 Beta 测试阶段，功能与服务正在持续开发和调整中。")

                    noticeSection(title: "在试运行期间，可能会出现：", items: riskItems)

                    paragraph("因此，当前阶段产生的部分用户数据可能不会被永久保留，包括但不限于：")

                    noticeSection(title: nil, items: dataItems)

                    paragraph("请勿将 Beta 阶段服务用于重要数据的长期存储。")
                    paragraph("后续正式版本上线后，圈子系统与数据机制会逐步稳定完善。")
                    paragraph("感谢大家参与测试与反馈 🥔")
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Beta 说明")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🥔")
                .font(.system(size: 38))

            Text("土豆圈 Beta 试运行说明")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)
        }
    }

    private func noticeSection(title: String?, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(item)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(.secondary)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
}

final class CircleFeedPostCache {
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
