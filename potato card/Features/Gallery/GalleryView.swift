//
//  GalleryView.swift
//  potato card
//

import PhotosUI
import SwiftUI

struct GalleryView: View {
    let onTransferToDevice: (Data) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var photos: [GalleryPhoto] = []
    @State private var selectedPhotoSet: SelectedPhotoSet?
    @State private var isImporting = false

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
        .sheet(item: $selectedPhotoSet) { set in
            GalleryImageViewer(
                photos: set.photos,
                initialIndex: set.initialIndex,
                onTransferToDevice: onTransferToDevice,
                onRenamePhoto: handleRenamePhoto
            )
            .presentationDetents([.height(560)])
            .presentationDragIndicator(.visible)
        }
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
                        Button(role: .destructive) {
                            deletePhoto(photo)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.bottom, 12)
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

private struct GalleryImageViewer: View {
    let photos: [GalleryPhoto]
    let initialIndex: Int
    let onTransferToDevice: (Data) -> Void
    // 由外层 GalleryView 提供，收到“修改名称”后同步到上层状态。
    var onRenamePhoto: ((UUID, String) -> Void)? = nil

    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedIndex: Int
    @State private var transferRequest: GalleryTransferRequest?
    @State private var pendingTransferData: Data?
    @State private var pendingTransferImage: UIImage?
    // 记录哪些照片已保存了“手动调整”状态，用来驱动预览与“手动调整”按钮的黄色指示。
    @State private var customizedPhotoIDs: Set<UUID> = []
    // 在 sheet 里修改过名称后本地缓存，只读走外层 photos 会丢掉变更。
    @State private var renamedTitles: [UUID: String] = [:]

    init(
        photos: [GalleryPhoto],
        initialIndex: Int,
        onTransferToDevice: @escaping (Data) -> Void,
        onRenamePhoto: ((UUID, String) -> Void)? = nil
    ) {
        self.photos = photos
        self.initialIndex = initialIndex
        self.onTransferToDevice = onTransferToDevice
        self.onRenamePhoto = onRenamePhoto
        _selectedIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color.black : Color.white)
                    .ignoresSafeArea()

                devicePreview

                VStack {
                    Spacer()

                    VStack(spacing: 10) {
                        transferStatusView

                        // 主操作：使用 TransferProgressButton。空闲时为强调色胶囊按钮；
                        // 传输/等待时按钮自身复用为苹果风格的进度条，避免 .borderedProminent
                        // 在 disabled 状态下丢失背景色的问题。
                        TransferProgressButton(
                            idleTitle: "传输到设备",
                            inProgressTitle: "传输中",
                            progress: bleService.transferProgress,
                            isInProgress: isTransferInProgress,
                            isEnabled: activeDevice != nil,
                            action: transferSelectedPhotoDirectly
                        )
                        .frame(minWidth: 180)

                        // 次操作：使用系统 bordered + capsule。当照片有非默认调整时把 tint 设为
                        // .yellow（系统强调色之一，自动适配暗色模式），保留“黄色提示”语义。
                        Button(action: openManualAdjustment) {
                            Label("手动调整", systemImage: "slider.horizontal.3")
                                .frame(minWidth: 100)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .controlSize(.regular)
                        .tint(currentPhotoIsCustomized ? .yellow : .secondary)
                        .disabled(isTransferInProgress)
                    }
                    .padding(.bottom, 10)
                    .offset(y: 20)
                }
            }
            .sheet(item: $transferRequest) { request in
                TransferSheetView(
                    sourceImage: request.photo.image,
                    title: renamedTitles[request.photo.id] ?? request.photo.title,
                    editStateKey: .gallery(request.photo.id),
                    onTransferSucceeded: {
                        onTransferToDevice(request.photo.imageData)
                        dismiss()
                    },
                    onRename: onRenamePhoto.map { rename in
                        { newTitle in
                            renamedTitles[request.photo.id] = newTitle
                            rename(request.photo.id, newTitle)
                        }
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: transferRequest?.id) { _, _ in
                // sheet 打开/关闭后重新加载调整状态，让一级页面的预览和黄色指示同步更新。
                refreshCustomizedPhotoIDs()
            }
            .task {
                refreshCustomizedPhotoIDs()
            }
            .onChange(of: bleService.transferPhase) { _, phase in
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text(renamedTitles[photos[selectedIndex].id] ?? photos[selectedIndex].title)
                        .font(.headline)
                }
            }
        }
    }

    @ViewBuilder
    private var transferStatusView: some View {
        // 进度展示已经合并到 TransferProgressButton 自身，这里只在失败时显示错误描述。
        if case .failed = bleService.transferPhase, let errorMessage = bleService.errorMessage {
            Text(errorMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private func transferSelectedPhotoDirectly() {
        guard let device = activeDevice else { return }

        let photo = photos[selectedIndex]
        // 传输这张照片时默认也要使用用户保存过的“手动调整”，跟预览保持一致。
        let savedAdjustment = TransferEditStateStore.load(for: .gallery(photo.id))
        let adjustment = savedAdjustment ?? .default
        let fitMode: EInkImageFitMode = (savedAdjustment != nil && adjustment != .default) ? .manual : .centerCrop
        let transferImage = transferImage(from: photo.image, device: device, fitMode: fitMode, adjustment: adjustment)
        let displayImage = displayImage(from: photo.image, device: device, fitMode: fitMode, adjustment: adjustment)
        pendingTransferData = photo.imageData
        pendingTransferImage = displayImage
        bleService.transfer(image: transferImage, displayImage: displayImage, to: device)
    }

    private func openManualAdjustment() {
        pendingTransferData = nil
        pendingTransferImage = nil
        transferRequest = GalleryTransferRequest(photo: photos[selectedIndex])
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
        bleService.transferPhase == .preparing || bleService.transferPhase == .transferring
    }

    private var devicePreview: some View {
        ZStack {
            TabView(selection: $selectedIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    AdjustedPhotoPreview(
                        image: photo.image,
                        adjustment: savedAdjustment(for: photo),
                        screenSize: CGSize(width: 186, height: 280),
                        renderTargetSize: renderTargetSize
                    )
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

            Image("ink_tatoo2")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220)
                .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 10)
                .allowsHitTesting(false)
        }
        .frame(width: 220, height: 352)
        .offset(y: -60)
    }

    private var renderTargetSize: CGSize {
        activeDevice?.profile.pixelSize ?? EInkDeviceProfile.fallback.pixelSize
    }

    private var currentPhotoIsCustomized: Bool {
        guard photos.indices.contains(selectedIndex) else { return false }
        return customizedPhotoIDs.contains(photos[selectedIndex].id)
    }

    // 加载某张照片对应的“手动调整”状态；缺省值代表没有自定义。
    private func savedAdjustment(for photo: GalleryPhoto) -> EInkManualAdjustment {
        TransferEditStateStore.load(for: .gallery(photo.id)) ?? .default
    }

    private func refreshCustomizedPhotoIDs() {
        let customized = photos.compactMap { photo -> UUID? in
            guard let saved = TransferEditStateStore.load(for: .gallery(photo.id)),
                  saved != .default else {
                return nil
            }
            return photo.id
        }
        customizedPhotoIDs = Set(customized)
    }
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

private struct GalleryTransferRequest: Identifiable {
    let id = UUID()
    let photo: GalleryPhoto
}

private struct GalleryView_Previews: PreviewProvider {
    static var previews: some View {
        GalleryView(onTransferToDevice: { _ in })
            .environmentObject(BleTransferService())
    }
}
