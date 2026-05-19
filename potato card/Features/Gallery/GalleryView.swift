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
            .presentationDetents([.height(560)])
            .presentationDragIndicator(.visible)
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
    // “原地调整”状态机：viewer 不再叠一层 sheet，而是让同一张“土豆片”
    // 卡片直接变成可交互的编辑面板。isEditing == true 时：
    //   · 底部按钮 morph 为滑块 + 取消/保存
    //   · 屏幕照片接手与提供拖动 / 双指缩放 / 旋转
    //   · TabView 换成单图显示，避免编辑手势与翻页手势冲突
    @State private var isEditing = false
    @State private var draftAdjustment = EInkManualAdjustment.default
    @State private var gestureScaleStart: CGFloat = 1
    @State private var gestureRotationStart: CGFloat = 0
    @State private var gestureOffsetStart: CGSize = .zero
    // 底部上滑累计位移：仅用于判断是否达到进入编辑阈值，不再驱动提示胶囊动画。
    @State private var swipeUpDragOffset: CGFloat = 0
    private let swipeUpTriggerThreshold: CGFloat = 56

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
            ZStack {
                viewerBackgroundColor
                    .ignoresSafeArea()

                devicePreview

                if isContentLocked {
                    lockedContentTitle
                        .allowsHitTesting(false)
                }

                VStack {
                    Spacer()

                    bottomContent
                        .padding(.bottom, isContentLocked ? 28 : 10)
                        .offset(y: isContentLocked ? 0 : 20)
                        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: isEditing)
                }
                .contentShape(Rectangle())
                .simultaneousGesture((isContentLocked || isEditing) ? nil : swipeUpGesture)
                .accessibilityAction(named: "进入手动调整") {
                    guard !isContentLocked, !isTransferInProgress, !isEditing else { return }
                    enterEditMode()
                }
            }
            .onChange(of: selectedIndex) { _ in
                // 切到另一张图时，如果当前在编辑模式，把草稿重新对齐到新图的已保存值。
                if isEditing {
                    draftAdjustment = savedAdjustment(for: photos[selectedIndex])
                    resetGestureBaselines()
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
                    ToolbarItem(placement: .principal) {
                        Text(toolbarTitle)
                            .font(.headline)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        // 编辑模式下不显示分享菜单；保存 / 取消由底部主操作区接管，
                        // 避免顶部和底部出现两套并行的退出入口。
                        if !isEditing, let onRequestShare {
                            shareMenu(onRequestShare: onRequestShare)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Bottom morph

    @ViewBuilder
    private var bottomContent: some View {
        if isEditing {
            editingControls
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                ))
        } else {
            viewerControls
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .opacity.combined(with: .move(edge: .bottom))
                ))
        }
    }

    private var viewerControls: some View {
        VStack(spacing: 10) {
            transferStatusView

            Button(action: transferSelectedPhotoDirectly) {
                transferButtonLabel
            }
            .buttonStyle(.plain)
            .disabled(activeDevice == nil)

            if !isContentLocked {
                Button {
                    enterEditMode()
                } label: {
                    Label("手动调整", systemImage: "slider.horizontal.3")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .tint(currentPhotoIsCustomized ? .yellow : .secondary)
                .disabled(isTransferInProgress)
            }
        }
    }

    private var editingControls: some View {
        // 内嵌的调整面板：滑块与 TransferSheetView 的几何完全一致，
        // 但所有操作就地完成，没有第二张 sheet / 卡片堆叠。
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                sliderRow(title: "缩放", value: $draftAdjustment.scale, range: 0.25...3, format: scalePercent)
                sliderRow(title: "旋转", value: $draftAdjustment.rotation, range: -.pi...(.pi), format: rotationDegrees)
                sliderRow(title: "水平", value: $draftAdjustment.offsetX, range: -160...160, format: offsetText)
                sliderRow(title: "垂直", value: $draftAdjustment.offsetY, range: -160...160, format: offsetText)
            }
            .padding(.horizontal, 16)

            HStack(spacing: 12) {
                Button(role: .cancel) {
                    cancelEditMode()
                } label: {
                    Text("取消")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)

                Button {
                    saveEditMode()
                } label: {
                    Text("保存")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
            }
            .padding(.horizontal, 16)
        }
        .background(
            // 给底部加一层浅薄的 .bar 材质，让滑块从视觉上脱离背景，
            // 而不是浮在透明区域上。
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.bar)
                .padding(.horizontal, 8)
        )
        .padding(.horizontal, -8)
    }

    private func sliderRow(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        format: @escaping (CGFloat) -> String
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)

            Slider(value: value, in: range)

            Text(format(value.wrappedValue))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
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

    // MARK: - Edit-mode helpers

    private func enterEditMode() {
        guard !isTransferInProgress else { return }
        draftAdjustment = savedAdjustment(for: photos[selectedIndex])
        resetGestureBaselines()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            isEditing = true
        }
    }

    private func saveEditMode() {
        let photo = photos[selectedIndex]
        let key = editStateKeyForPhoto(photo)
        if draftAdjustment == .default {
            TransferEditStateStore.delete(for: key)
        } else {
            TransferEditStateStore.save(draftAdjustment, for: key)
        }
        refreshCustomizedPhotoIDs()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isEditing = false
        }
    }

    private func cancelEditMode() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isEditing = false
        }
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
            // 编辑模式下只显示当前照片并接所有手势；
            // 非编辑模式下保持原有的 TabView，可以左右翻页。
            if isEditing, photos.indices.contains(selectedIndex) {
                editableScreen(for: photos[selectedIndex])
                    .frame(width: 186, height: 280)
                    .mask(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .frame(width: 186, height: 280)
                    )
                    .offset(y: -19)
            } else {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        screenPreview(for: photo)
                        .frame(width: 186, height: 280)
                        .tag(index)
                    }
                }
                .frame(width: 186, height: 280)
                .tabViewStyle(.page(indexDisplayMode: .never))
                .mask(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .frame(width: 186, height: 280)
                )
                .offset(y: -19)
            }

            Image("ink_tatoo2")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220)
                .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 10)
                .allowsHitTesting(false)
        }
        .frame(width: 220, height: 352)
        .offset(y: isContentLocked ? -14 : -60)
    }

    // 主预览底部的上滑手势：只在向上拖动时收集累计位移，松手到达阈值则进入编辑模式。
    // 用 simultaneousGesture 接入，确保不会抢掉 sheet 自带的下滑关闭手势。
    // 不再驱动任何可见动画（提示胶囊取消），该手势只是「隐形」加速器。
    private var swipeUpGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                let dy = value.translation.height
                guard dy <= 0 else {
                    swipeUpDragOffset = 0
                    return
                }
                swipeUpDragOffset = dy
            }
            .onEnded { value in
                let shouldTrigger = -swipeUpDragOffset >= swipeUpTriggerThreshold
                    || value.predictedEndTranslation.height <= -swipeUpTriggerThreshold * 1.2
                swipeUpDragOffset = 0
                if shouldTrigger, !isTransferInProgress, !isEditing {
                    enterEditMode()
                }
            }
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
        if isContentLocked {
            LockedPhotoPreview(
                image: photo.image,
                adjustment: savedAdjustment(for: photo),
                screenSize: CGSize(width: 186, height: 280),
                renderTargetSize: renderTargetSize,
                message: lockedPreviewText
            )
        } else {
            AdjustedPhotoPreview(
                image: photo.image,
                adjustment: savedAdjustment(for: photo),
                screenSize: CGSize(width: 186, height: 280),
                renderTargetSize: renderTargetSize
            )
        }
    }

    // 编辑模式下的预览：几何与 AdjustedPhotoPreview 同源，但读取 draftAdjustment
    // 并接 pinch / rotate / drag 三者合手势。
    @ViewBuilder
    private func editableScreen(for photo: GalleryPhoto) -> some View {
        GeometryReader { proxy in
            let baseScale = max(proxy.size.width / photo.image.size.width, proxy.size.height / photo.image.size.height)
            let offsetScale = min(proxy.size.width / renderTargetSize.width, proxy.size.height / renderTargetSize.height)

            Image(uiImage: photo.image)
                .resizable()
                .interpolation(.medium)
                .frame(width: photo.image.size.width * baseScale, height: photo.image.size.height * baseScale)
                .scaleEffect(draftAdjustment.scale)
                .rotationEffect(.radians(Double(draftAdjustment.rotation)))
                .offset(x: draftAdjustment.offsetX * offsetScale, y: draftAdjustment.offsetY * offsetScale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color.white)
        .clipped()
        .contentShape(Rectangle())
        .gesture(editableCombinedGesture)
    }

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
