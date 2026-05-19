//
//  GalleryView.swift
//  potato card
//

import PhotosUI
import SwiftUI

struct GalleryView: View {
    let onTransferToDevice: (Data) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var photos: [GalleryPhoto] = []
    @State private var selectedPhotoSet: SelectedPhotoSet?
    @State private var isImporting = false
    // 长按缩略图弹出的「手动调整」入口走的独立 sheet。复用 TransferSheetView，
    // 与一级页面的手动调整完全一致，省去用户先打开预览再点按钮的两步流程。
    @State private var adjustingPhoto: GalleryPhoto?
    // 长按缩略图触发的「分享到圈子 / 漂流瓶」入口。
    @State private var shareDestination: GalleryShareDestination?
    @State private var shareToast: String?
    // 从一级 viewer 顶部分享菜单触发时，把目标先存这里，等 viewer dismiss 动画结束再开
    // share sheet，避免两张 sheet 在同一帧重叠出现「两张卡片」。
    @State private var pendingShareAfterDismiss: GalleryShareDestination?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if photos.isEmpty {
                emptyState
            } else {
                photoGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await loadCachedPhotosIfNeeded()
        }
        .task(id: selectedItems) {
            await importSelectedItems()
        }
        .onChange(of: scenePhase) { phase in
            // 后台快捷指令可能在 App 不在前台时写入新的图库条目，
            // 重新回前台时从磁盘合并一次，避免列表停在旧状态。
            guard phase == .active else { return }
            Task { await refreshNewPhotosFromDisk() }
        }
        .sheet(item: $selectedPhotoSet) { set in
            GalleryImageViewer(
                photos: set.photos,
                initialIndex: set.initialIndex,
                onTransferToDevice: onTransferToDevice,
                onRenamePhoto: handleRenamePhoto,
                onRequestShare: { destination in
                    // viewer 把分享请求挂到 GalleryView，等下面 onChange 检测到 viewer
                    // 真正被 dismiss 后再展示 share sheet，避免两张 sheet 同时出现。
                    pendingShareAfterDismiss = destination
                }
            )
            // detent / dragIndicator 都由 GalleryImageViewer 内部声明，
            // 因为编辑模式需要在 .height(560) 和 .large 之间切换。
        }
        .onChange(of: selectedPhotoSet?.id) { newID in
            // viewer 关闭瞬间触发：把挂起的分享目标接力到 shareDestination sheet。
            guard newID == nil, let pending = pendingShareAfterDismiss else { return }
            pendingShareAfterDismiss = nil
            Task { @MainActor in
                // 等 viewer 的 dismiss 动画走完再开 share sheet，
                // 没有这个延时 SwiftUI 会拒绝二次 sheet（item 设置被忽略）。
                try? await Task.sleep(nanoseconds: 350_000_000)
                shareDestination = pending
            }
        }
        .sheet(item: $adjustingPhoto) { photo in
            // 长按 → 调整：直接打开二级手动调整面板，与一级页面用的是同一个组件。
            TransferSheetView(
                sourceImage: photo.image,
                title: photo.title,
                editStateKey: .gallery(photo.id),
                onTransferSucceeded: {
                    onTransferToDevice(photo.imageData)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $shareDestination) { destination in
            GalleryShareSheet(
                destination: destination,
                onPublishSucceeded: { dest in
                    let title: String = {
                        switch dest {
                        case .circle: return "已发布到圈子"
                        case .driftBottle: return "漂流瓶已扔进海里"
                        }
                    }()
                    shareToast = title
                },
                onPublishFailed: { message in
                    shareToast = "分享失败：\(message)"
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .top) {
            if let shareToast {
                Text(shareToast)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        withAnimation(.easeInOut(duration: 0.25)) {
                            self.shareToast = nil
                        }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: shareToast)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("图库")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(primaryTextColor)

            Spacer()

            PhotosPicker(
                selection: $selectedItems,
                maxSelectionCount: nil,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))

                    Text(isImporting ? "导入中" : "添加照片")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(primaryTextColor)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(buttonFillColor, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(buttonStrokeColor, lineWidth: 1)
                )
            }
            .disabled(isImporting)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("从系统相册中选择照片，传到设备屏幕里预览。")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(secondaryTextColor)

            Text("点右上角“添加照片”即可导入。")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(secondaryTextColor.opacity(0.92))
        }
        .padding(.top, 6)
    }

    private var photoGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: gridColumns, spacing: 3) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    Button {
                        selectedPhotoSet = SelectedPhotoSet(photos: photos, initialIndex: index)
                    } label: {
                        photoThumbnail(photo)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            adjustingPhoto = photo
                        } label: {
                            Label("调整", systemImage: "slider.horizontal.3")
                        }

                        Section("分享") {
                            Button {
                                shareDestination = .circle(photo: photo)
                            } label: {
                                Label("分享到圈子", systemImage: "person.2.circle")
                            }

                            Button {
                                shareDestination = .driftBottle(photo: photo)
                            } label: {
                                Label("分享到漂流瓶", systemImage: "paperplane")
                            }
                        }

                        Section {
                            Button(role: .destructive) {
                                deletePhoto(photo)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.bottom, AppBottomBarMetrics.scrollContentBottomPadding)
        }
        .padding(.horizontal, -24)
    }

    private func photoThumbnail(_ photo: GalleryPhoto) -> some View {
        GeometryReader { proxy in
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.width)
                .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
    }

    private func importSelectedItems() async {
        guard !selectedItems.isEmpty else { return }

        isImporting = true
        let items = selectedItems
        selectedItems = []

        let startIndex = photos.count
        var importedPhotos: [GalleryPhoto] = []
        importedPhotos.reserveCapacity(items.count)

        for (offset, item) in items.enumerated() {
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let photo = GalleryCacheStore.appendPhoto(
                    data: data,
                    title: "照片 \(startIndex + offset + 1)"
                )
            else {
                continue
            }

            importedPhotos.append(photo)
        }

        if !importedPhotos.isEmpty {
            photos.insert(contentsOf: importedPhotos, at: 0)
        }

        isImporting = false
    }

    private func loadCachedPhotosIfNeeded() async {
        guard photos.isEmpty else { return }
        // 缓存图片可能较多，后台读取和解码，避免首次进入页面卡主线程。
        let cachedPhotos = await Task.detached(priority: .utility) {
            GalleryCacheStore.loadPhotos()
        }.value

        guard photos.isEmpty else { return }
        photos = cachedPhotos
    }

    // 从后台回前台时调用：只拾磁盘头部那些在内存里不存在的新 id。
    // GalleryCacheStore.appendPhoto 总是 insert(at: 0)，所以新照片一定在磁盘索引的前缀。
    private func refreshNewPhotosFromDisk() async {
        let cached = await Task.detached(priority: .utility) {
            GalleryCacheStore.loadPhotos()
        }.value

        guard !cached.isEmpty else { return }

        if photos.isEmpty {
            photos = cached
            return
        }

        let knownIDs = Set(photos.map(\.id))
        let newPhotos = Array(cached.prefix(while: { !knownIDs.contains($0.id) }))
        guard !newPhotos.isEmpty else { return }

        photos.insert(contentsOf: newPhotos, at: 0)
    }

    private func deletePhoto(_ photo: GalleryPhoto) {
        photos.removeAll { $0.id == photo.id }
        GalleryCacheStore.deletePhoto(id: photo.id)
        TransferEditStateStore.delete(for: .gallery(photo.id))
    }

    // 从二级 Sheet 收到重命名后：实时更新内存里的列表，同时写回磁盘索引。
    private func handleRenamePhoto(id: UUID, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        let existing = photos[index]
        guard existing.title != trimmed else { return }
        photos[index] = GalleryPhoto(
            id: existing.id,
            imageData: existing.imageData,
            image: existing.image,
            title: trimmed
        )
        GalleryCacheStore.renamePhoto(id: id, to: trimmed)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.92)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.54) : Color.black.opacity(0.42)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }

    private var buttonFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.05)
    }

    private var buttonStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }
}

private struct SelectedPhotoSet: Identifiable {
    let id: String
    let photos: [GalleryPhoto]
    let initialIndex: Int

    init(photos: [GalleryPhoto], initialIndex: Int) {
        self.photos = photos
        self.initialIndex = initialIndex
        self.id = "\(photos.map(\.id.uuidString).joined(separator: "|"))-\(initialIndex)"
    }
}

struct GalleryImageViewer: View {
    let photos: [GalleryPhoto]
    let initialIndex: Int
    let onTransferToDevice: (Data) -> Void
    let editStateKeyForPhoto: (GalleryPhoto) -> TransferEditStateKey
    let transferImageProvider: ((GalleryPhoto) async throws -> GalleryPreparedTransferImage)?
    let isContentLocked: Bool
    let lockedPreviewText: String
    let transferButtonTitle: String
    // 由外层 GalleryView 提供，收到“修改名称”后同步到上层状态。
    var onRenamePhoto: ((UUID, String) -> Void)? = nil

    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedIndex: Int
    @State private var pendingTransferData: Data?
    @State private var pendingTransferImage: UIImage?
    @State private var isPreparingTransferImage = false
    @State private var transferPreparationError: String?
    // 记录哪些照片已保存了“手动调整”状态，用来驱动预览与“手动调整”按钮的黄色指示。
    @State private var customizedPhotoIDs: Set<UUID> = []
    // 在 sheet 里修改过名称后本地缓存，只读走外层 photos 会丢掉变更。
    @State private var renamedTitles: [UUID: String] = [:]
    // 编辑状态完全由「当前 sheet 高度」驱动：.large = 全屏编辑，
    // .height(560) = 预览。不再维护 isEditing/draft 二重状态机，
    // 也不再需要自定义上滑手势——原生 sheet detent 拖动就是调整入口。
    @State private var selectedDetent: PresentationDetent = .height(560)
    @State private var draftAdjustment = EInkManualAdjustment.default
    // 进入编辑模式时快照当前图的「已保存调整」，
    // 用户点「取消」时把 draft 还原为快照、再收起 sheet，
    // 于是 persistDraftIfNeeded 写回的与原状态一致，二进制到量上就是「未修改」。
    @State private var preEditSnapshot: EInkManualAdjustment = .default
    @State private var gestureScaleStart: CGFloat = 1
    @State private var gestureRotationStart: CGFloat = 0
    @State private var gestureOffsetStart: CGSize = .zero

    private var isExpanded: Bool { selectedDetent == .large }

    // 点击 toolbar 右上角分享 → 由外层 GalleryView 接管并在 viewer dismiss 后弹分享 sheet，
    // 避免继续出现两张 sheet 叠加在一起的“两张卡片”状况。
    var onRequestShare: ((GalleryShareDestination) -> Void)? = nil

    init(
        photos: [GalleryPhoto],
        initialIndex: Int,
        onTransferToDevice: @escaping (Data) -> Void,
        editStateKeyForPhoto: @escaping (GalleryPhoto) -> TransferEditStateKey = { .gallery($0.id) },
        transferImageProvider: ((GalleryPhoto) async throws -> GalleryPreparedTransferImage)? = nil,
        isContentLocked: Bool = false,
        lockedPreviewText: String = "点击传输以查看",
        transferButtonTitle: String = "传输到设备",
        onRenamePhoto: ((UUID, String) -> Void)? = nil,
        onRequestShare: ((GalleryShareDestination) -> Void)? = nil
    ) {
        self.photos = photos
        self.initialIndex = initialIndex
        self.onTransferToDevice = onTransferToDevice
        self.editStateKeyForPhoto = editStateKeyForPhoto
        self.transferImageProvider = transferImageProvider
        self.isContentLocked = isContentLocked
        self.lockedPreviewText = lockedPreviewText
        self.transferButtonTitle = transferButtonTitle
        self.onRenamePhoto = onRenamePhoto
        self.onRequestShare = onRequestShare
        _selectedIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        NavigationStack {
            // 把整个 viewer 拆成「土豆片预览 + 控件」两个上下排列的区块；
            // 上半部分高度固定 ≈ 352pt，下半部分在 .height(560) 时只显示按钮，
            // 在 .large 时滑入滑块面板，整个视图始终是同一级 hierarchy，
            // 不再出现两张 sheet 叠加 / 二级 morph 的情况。
            VStack(spacing: 0) {
                topPreviewSection
                    .frame(maxWidth: .infinity)
                    .frame(height: isContentLocked ? 360 : 352)

                bottomScrollSection
            }
            .background(viewerBackgroundColor.ignoresSafeArea())
            .onChange(of: selectedIndex) { _ in
                // 切到另一张图：把草稿重置为新图已保存值。
                draftAdjustment = savedAdjustment(for: photos[selectedIndex])
                resetGestureBaselines()
            }
            .onAppear {
                // 进入 viewer 时把当前图的已保存调整带进 draft，
                // 这样切到 .large 直接就是上次的位置。
                if photos.indices.contains(selectedIndex) {
                    draftAdjustment = savedAdjustment(for: photos[selectedIndex])
                    resetGestureBaselines()
                }
            }
            .onChange(of: isExpanded) { expanded in
                // 收起时把当前 draft 持久化；这样用户拖回小尺寸即等同于「保存」，
                // 与系统照片编辑/系统相机的「拉下来即应用」交互一致。
                if !expanded {
                    persistDraftIfNeeded()
                } else {
                    // 拉起即视为进入了一次新的「编辑会话」：把当前 saved 值作为
                    // 「取消」要回退到的快照。不管是点按钮还是直接拖动 sheet 上来都会走这里。
                    if photos.indices.contains(selectedIndex) {
                        preEditSnapshot = savedAdjustment(for: photos[selectedIndex])
                    }
                    resetGestureBaselines()
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            }
            .task {
                refreshCustomizedPhotoIDs()
            }
            .onChange(of: bleService.transferPhase) { phase in
                guard phase == .succeeded, let data = pendingTransferData else { return }
                if let pendingTransferImage {
                    bleService.markLastTransferredImage(pendingTransferImage)
                }
                onTransferToDevice(data)
                pendingTransferData = nil
                pendingTransferImage = nil
                dismiss()
            }
            .toolbar {
                if !isContentLocked {
                    ToolbarItem(placement: .topBarLeading) {
                        if isExpanded {
                            // 编辑模式专用「取消」：只撤销本次调整，
                            // 已保存过的调整仍保留不变。
                            Button("取消") {
                                cancelEditMode()
                            }
                        }
                    }

                    ToolbarItem(placement: .principal) {
                        Text(toolbarTitle)
                            .font(.headline)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        if isExpanded {
                            // 全屏调整状态下右上角变成「完成」，等同于拖回小尺寸——
                            // 给键盘焦点 / 无障碍用户一个显式的退出通道。
                            Button("完成") {
                                collapseToPreview()
                            }
                            .fontWeight(.semibold)
                        } else if let onRequestShare {
                            shareMenu(onRequestShare: onRequestShare)
                        }
                    }
                }
            }
        }
        // 同一张 sheet 用 .height(560) ↔ .large 两个 detent，
        // 把「全屏编辑」做成原生交互：上拉 = 进入编辑，下拉 = 回到预览。
        .presentationDetents(
            isContentLocked ? [.height(560)] : [.height(560), .large],
            selection: $selectedDetent
        )
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    // MARK: - Layout 拆分

    // 上半部：永远是「土豆片」预览。.large 时屏幕区域接手手势，
    // 用户可以直接拖动 / 双指缩放 / 旋转图片本身。
    private var topPreviewSection: some View {
        ZStack {
            devicePreview

            if isContentLocked {
                lockedContentTitle
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 下半部：在 .height(560) 状态下是双按钮；在 .large 时跟着 ScrollView 滑入滑块面板。
    private var bottomScrollSection: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                primaryControls
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                if isExpanded {
                    adjustmentSection
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.bottom, 24)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: isExpanded)
    }

    // 上下文按钮：传输到设备 + 手动调整 / 重置
    private var primaryControls: some View {
        VStack(spacing: 10) {
            transferStatusView

            Button(action: transferSelectedPhotoDirectly) {
                transferButtonLabel
            }
            .buttonStyle(.plain)
            .disabled(activeDevice == nil)

            if !isContentLocked {
                Button {
                    if isExpanded {
                        // 已经在编辑：第二次点 = 重置当前调整。
                        withAnimation(.easeOut(duration: 0.2)) {
                            draftAdjustment = .default
                        }
                        resetGestureBaselines()
                    } else {
                        expandToEdit()
                    }
                } label: {
                    Label(isExpanded ? "重置" : "手动调整",
                          systemImage: isExpanded ? "arrow.counterclockwise" : "slider.horizontal.3")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .tint(currentPhotoIsCustomized || draftAdjustment != .default ? .yellow : .secondary)
                .disabled(isTransferInProgress)
            }
        }
    }

    // .large 时显示的滑块面板。视觉上是一个标准的「分组」section，
    // 不再用上一版那种圆角浮卡——避免「太丑 / 没全屏」的观感。
    private var adjustmentSection: some View {
        VStack(spacing: 0) {
            sliderRow(title: "缩放", value: $draftAdjustment.scale, range: 0.25...3, format: scalePercent)
            Divider().padding(.leading, 56)
            sliderRow(title: "旋转", value: $draftAdjustment.rotation, range: -.pi...(.pi), format: rotationDegrees)
            Divider().padding(.leading, 56)
            sliderRow(title: "水平", value: $draftAdjustment.offsetX, range: -160...160, format: offsetText)
            Divider().padding(.leading, 56)
            sliderRow(title: "垂直", value: $draftAdjustment.offsetY, range: -160...160, format: offsetText)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func sliderRow(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        format: @escaping (CGFloat) -> String
    ) -> some View {
        // 跟随系统 Form 里的 LabeledContent 样式：左侧标题 + 数值，右侧滑块。
        // 这样与其他 iOS 原生调整面板（控制中心 / 照片 markup 等）视觉一致。
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(format(value.wrappedValue))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 56, alignment: .leading)

            Slider(value: value, in: range)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func scalePercent(_ value: CGFloat) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func rotationDegrees(_ value: CGFloat) -> String {
        let degrees = value * 180 / .pi
        return String(format: "%.0f°", degrees)
    }

    private func offsetText(_ value: CGFloat) -> String {
        "\(Int(value.rounded()))"
    }

    // 顶部 toolbar 分享菜单
    @ViewBuilder
    private func shareMenu(onRequestShare: @escaping (GalleryShareDestination) -> Void) -> some View {
        Menu {
            Button {
                let photo = photos[selectedIndex]
                onRequestShare(.circle(photo: photo))
                dismiss()
            } label: {
                Label("分享到圈子", systemImage: "person.2.circle")
            }

            Button {
                let photo = photos[selectedIndex]
                onRequestShare(.driftBottle(photo: photo))
                dismiss()
            } label: {
                Label("分享到漂流瓶", systemImage: "paperplane")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16, weight: .semibold))
        }
        .accessibilityLabel("分享")
    }

    // MARK: - Detent 过渡

    private func expandToEdit() {
        guard !isTransferInProgress else { return }
        // 进入 .large 之前先把 draft 重新对齐到当前图的已保存值，
        // 避免上一张图的 draft 被带到这一张；同时把这一刻的状态作为
        // 「取消」需要回滚到的快照。
        let saved = savedAdjustment(for: photos[selectedIndex])
        draftAdjustment = saved
        preEditSnapshot = saved
        resetGestureBaselines()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
            selectedDetent = .large
        }
    }

    private func collapseToPreview() {
        // 同步先持久化：onChange(of: isExpanded) 是异步的，body 会在那之前
        // 重新渲染一次，screenPreview 又会按 storage 读取「上一次保存的值」，
        // 视觉上等同于「编辑完下拉时图片回到上次保存位置再跳回来」。
        persistDraftIfNeeded()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
            selectedDetent = .height(560)
        }
    }

    private func cancelEditMode() {
        // 把 draft 回退到进入编辑前的快照，再走正常 collapse 路径；
        // 由于 persistDraftIfNeeded 写回的就是快照值，相当于本次会话从未发生。
        draftAdjustment = preEditSnapshot
        resetGestureBaselines()
        collapseToPreview()
    }

    private func persistDraftIfNeeded() {
        guard photos.indices.contains(selectedIndex) else { return }
        let photo = photos[selectedIndex]
        let key = editStateKeyForPhoto(photo)
        if draftAdjustment == .default {
            TransferEditStateStore.delete(for: key)
        } else {
            TransferEditStateStore.save(draftAdjustment, for: key)
        }
        refreshCustomizedPhotoIDs()
    }

    private func resetGestureBaselines() {
        gestureScaleStart = draftAdjustment.scale
        gestureRotationStart = draftAdjustment.rotation
        gestureOffsetStart = CGSize(width: draftAdjustment.offsetX, height: draftAdjustment.offsetY)
    }

    @ViewBuilder
    private var transferStatusView: some View {
        if isPreparingTransferImage {
            Text("正在获取原图")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else if let transferPreparationError {
            Text(transferPreparationError)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        } else if case .failed = bleService.transferPhase, let errorMessage = bleService.errorMessage {
            Text(errorMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private func transferSelectedPhotoDirectly() {
        guard !isTransferInProgress, let device = activeDevice else { return }

        let photo = photos[selectedIndex]
        transferPreparationError = nil

        if let transferImageProvider {
            isPreparingTransferImage = true
            Task {
                do {
                    let preparedImage = try await transferImageProvider(photo)
                    isPreparingTransferImage = false
                    startTransfer(
                        image: preparedImage.image,
                        imageData: preparedImage.imageData,
                        device: device,
                        photo: photo
                    )
                } catch {
                    isPreparingTransferImage = false
                    transferPreparationError = error.localizedDescription
                }
            }
            return
        }

        startTransfer(image: photo.image, imageData: photo.imageData, device: device, photo: photo)
    }

    private func startTransfer(image: UIImage, imageData: Data, device: BleDevice, photo: GalleryPhoto) {
        // 传输这张照片时默认也要使用用户保存过的“手动调整”，跟预览保持一致。
        let savedAdjustment = TransferEditStateStore.load(for: editStateKeyForPhoto(photo))
        let adjustment = savedAdjustment ?? .default
        let fitMode: EInkImageFitMode = (savedAdjustment != nil && adjustment != .default) ? .manual : .centerCrop
        let transferImage = transferImage(from: image, device: device, fitMode: fitMode, adjustment: adjustment)
        let displayImage = displayImage(from: image, device: device, fitMode: fitMode, adjustment: adjustment)
        pendingTransferData = imageData
        pendingTransferImage = displayImage
        bleService.transfer(image: transferImage, displayImage: displayImage, to: device)
    }

    private func transferImage(
        from image: UIImage,
        device: BleDevice,
        fitMode: EInkImageFitMode,
        adjustment: EInkManualAdjustment
    ) -> UIImage {
        EInkImageRenderer.renderForTransfer(
            image: image,
            targetSize: device.profile.pixelSize,
            fitMode: fitMode,
            adjustment: adjustment,
            profile: device.profile,
            ditherAlgorithm: bleService.ditherAlgorithm
        )
    }

    private func displayImage(
        from image: UIImage,
        device: BleDevice,
        fitMode: EInkImageFitMode,
        adjustment: EInkManualAdjustment
    ) -> UIImage {
        EInkImageRenderer.render(
            image: image,
            targetSize: device.profile.pixelSize,
            fitMode: fitMode,
            adjustment: adjustment
        )
    }

    private var activeDevice: BleDevice? {
        bleService.connectedDevice ?? bleService.selectedDevice
    }

    private var isTransferInProgress: Bool {
        if isPreparingTransferImage { return true }
        return bleService.transferPhase == .preparing || bleService.transferPhase == .transferring
    }

    private var primaryTransferButtonFillColor: Color {
        Color(red: 0.0, green: 0.48, blue: 1.0)
    }

    private var transferProgressPercent: Int {
        min(100, max(0, Int((bleService.transferProgress * 100).rounded())))
    }

    private var transferButtonProgressTitle: String {
        switch bleService.transferPhase {
        case _ where isPreparingTransferImage:
            return "正在获取原图"
        case .preparing:
            return "等待 \(transferProgressPercent)%"
        case .transferring:
            return "传输中 \(transferProgressPercent)%"
        default:
            return transferButtonTitle
        }
    }

    private var transferButtonLabel: some View {
        TransferProgressButtonLabel(
            title: transferButtonTitle,
            progressTitle: transferButtonProgressTitle,
            progress: bleService.transferProgress,
            isInProgress: isTransferInProgress,
            width: isContentLocked ? 190 : 140,
            height: 38,
            cornerRadius: 19,
            accentColor: primaryTransferButtonFillColor
        )
    }

    private var lockedContentTitle: some View {
        VStack {
            Text(toolbarTitle)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.horizontal, 28)
                .padding(.top, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var devicePreview: some View {
        ZStack {
            // 始终是一棵 TabView：expanded ↔ collapsed 切换时不再 swap view tree，
            // 只是给「当前选中那张」的 photo screen 切手势开关。这样 SwiftUI 不会
            // 在 detent 变化时给图片做位移动画（之前看到的「从左上向右下划」就是
            // editableScreen 与 TabView 两个不同 view tree 的 cross-fade 引起的）。
            // 全屏时禁用 TabView 翻页手势，避免编辑用的拖动跟翻页冲突。
            TabView(selection: $selectedIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    screenPreview(for: photo)
                        .frame(width: 186, height: 280)
                        .tag(index)
                }
            }
            .frame(width: 186, height: 280)
            .tabViewStyle(.page(indexDisplayMode: .never))
            // 编辑模式下关掉左右翻页，避免与拖动手势冲突。
            .allowsHitTesting(isExpanded ? false : true)
            .mask(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .frame(width: 186, height: 280)
            )
            .offset(y: -19)

            // 编辑模式下，在 TabView 上面叠一层透明手势捕获层；
            // 因为 TabView 内部的 SwiftUI Page 容器有时不会把 pinch / rotation 透
            // 给子 View，独立一层手势捕获最稳。下面 photo 的几何已经在
            // screenPreview/draftAdjustment 路径渲染，这一层只负责更新 draft。
            if isExpanded, photos.indices.contains(selectedIndex) {
                Color.clear
                    .frame(width: 186, height: 280)
                    .contentShape(Rectangle())
                    .offset(y: -19)
                    .gesture(editableCombinedGesture)
            }

            Image("ink_tatoo2")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220)
                .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 10)
                .allowsHitTesting(false)
        }
        .frame(width: 220, height: 352)
        // 上一版是在全屏 ZStack 里、需要向上挑逿跳过底部按钮的 .offset(y: -60)；
        // 现在在 VStack 里 devicePreview 被 topPreviewSection 的固定高度包住，
        // 不再需要偏移——之前的 -60 会让顶部灯柝逿进 nav bar 区域，
        // 表现为预览顶多了一条「白色 header」。
    }

    private var renderTargetSize: CGSize {
        activeDevice?.profile.pixelSize ?? EInkDeviceProfile.fallback.pixelSize
    }

    private var currentPhotoIsCustomized: Bool {
        guard photos.indices.contains(selectedIndex) else { return false }
        return customizedPhotoIDs.contains(photos[selectedIndex].id)
    }

    @ViewBuilder
    private func screenPreview(for photo: GalleryPhoto) -> some View {
        // 当前选中的那张图：直接读 draftAdjustment，避免「编辑完下拉 → body 已经
        // 重新渲染，但 onChange(of: isExpanded) 里的 persistDraftIfNeeded 尚未写
        // 回 TransferEditStateStore」造成一帧读到旧 saved 值的竞争（表现就是图片
        // 突然从编辑位置滑回未编辑位置）。其余照片走存储里的值，确保 TabView 翻
        // 页时看到各自的已保存调整。
        let adjustment: EInkManualAdjustment =
            (photos.indices.contains(selectedIndex) && photo.id == photos[selectedIndex].id)
                ? draftAdjustment
                : savedAdjustment(for: photo)

        if isContentLocked {
            LockedPhotoPreview(
                image: photo.image,
                adjustment: adjustment,
                screenSize: CGSize(width: 186, height: 280),
                renderTargetSize: renderTargetSize,
                message: lockedPreviewText
            )
        } else {
            AdjustedPhotoPreview(
                image: photo.image,
                adjustment: adjustment,
                screenSize: CGSize(width: 186, height: 280),
                renderTargetSize: renderTargetSize
            )
        }
    }

    // 编辑模式下用到的手势：直接更新 draftAdjustment；几何已经在
    // screenPreview 那一侧用 draftAdjustment 渲染了，所以这里只负责数值变更。
    private var editableCombinedGesture: some Gesture {
        let drag = DragGesture()
            .onChanged { value in
                draftAdjustment.offsetX = clampOffset(gestureOffsetStart.width + value.translation.width)
                draftAdjustment.offsetY = clampOffset(gestureOffsetStart.height + value.translation.height)
            }
            .onEnded { _ in
                gestureOffsetStart = CGSize(width: draftAdjustment.offsetX, height: draftAdjustment.offsetY)
            }

        let magnify = MagnificationGesture()
            .onChanged { value in
                draftAdjustment.scale = clampScale(gestureScaleStart * value)
            }
            .onEnded { _ in
                gestureScaleStart = draftAdjustment.scale
            }

        let rotate = RotationGesture()
            .onChanged { angle in
                draftAdjustment.rotation = clampRotation(gestureRotationStart + CGFloat(angle.radians))
            }
            .onEnded { _ in
                gestureRotationStart = draftAdjustment.rotation
            }

        return SimultaneousGesture(SimultaneousGesture(magnify, rotate), drag)
    }

    private func clampScale(_ value: CGFloat) -> CGFloat { min(max(value, 0.25), 3) }
    private func clampOffset(_ value: CGFloat) -> CGFloat { min(max(value, -160), 160) }
    private func clampRotation(_ value: CGFloat) -> CGFloat { min(max(value, -.pi), .pi) }

    // 加载某张照片对应的“手动调整”状态；缺省值代表没有自定义。
    private func savedAdjustment(for photo: GalleryPhoto) -> EInkManualAdjustment {
        TransferEditStateStore.load(for: editStateKeyForPhoto(photo)) ?? .default
    }

    private func refreshCustomizedPhotoIDs() {
        let customized = photos.compactMap { photo -> UUID? in
            guard let saved = TransferEditStateStore.load(for: editStateKeyForPhoto(photo)),
                  saved != .default else {
                return nil
            }
            return photo.id
        }
        customizedPhotoIDs = Set(customized)
    }

    private var viewerBackgroundColor: Color {
        colorScheme == .dark ? Color(.systemGroupedBackground) : Color.white
    }

    private var toolbarTitle: String {
        return renamedTitles[photos[selectedIndex].id] ?? photos[selectedIndex].title
    }
}

struct GalleryPreparedTransferImage {
    let imageData: Data
    let image: UIImage
}

// MARK: - 单张图片应用手动调整后的预览

// 复用 EInkDevicePreview 的几何公式，把 source image 按 (scale, rotation, offsetX, offsetY) 渲染到目标 screen 区域。
// 不做抖动，保留为彩色预览即可，用户在“一级”预览页面只需要看到布局；真正的传输图仍然走 EInkImageRenderer。
private struct AdjustedPhotoPreview: View {
    let image: UIImage
    let adjustment: EInkManualAdjustment
    let screenSize: CGSize
    let renderTargetSize: CGSize

    var body: some View {
        GeometryReader { proxy in
            let baseScale = max(proxy.size.width / image.size.width, proxy.size.height / image.size.height)
            let offsetScale = min(proxy.size.width / renderTargetSize.width, proxy.size.height / renderTargetSize.height)

            Image(uiImage: image)
                .resizable()
                .interpolation(.medium)
                .frame(width: image.size.width * baseScale, height: image.size.height * baseScale)
                .scaleEffect(adjustment.scale)
                .rotationEffect(.radians(Double(adjustment.rotation)))
                .offset(x: adjustment.offsetX * offsetScale, y: adjustment.offsetY * offsetScale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .clipped()
    }
}

private struct LockedPhotoPreview: View {
    let image: UIImage
    let adjustment: EInkManualAdjustment
    let screenSize: CGSize
    let renderTargetSize: CGSize
    let message: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AdjustedPhotoPreview(
                image: image,
                adjustment: adjustment,
                screenSize: screenSize,
                renderTargetSize: renderTargetSize
            )
            .scaleEffect(1.08)
            .blur(radius: 16, opaque: true)
            .saturation(0.9)
            .contrast(0.94)
            .overlay(Color.white.opacity(0.10))
            .overlay(Color.black.opacity(0.12))

            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: "lock.display")
                    .font(.system(size: 18, weight: .semibold))

                Text(message)
                    .font(.system(size: 11, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white.opacity(0.92))
            .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 3)
            .padding(10)
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .clipped()
    }
}

private struct GalleryView_Previews: PreviewProvider {
    static var previews: some View {
        GalleryView(onTransferToDevice: { _ in })
            .environmentObject(BleTransferService())
    }
}
