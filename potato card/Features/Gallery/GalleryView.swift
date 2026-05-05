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
                onTransferToDevice: onTransferToDevice
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

    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedIndex: Int
    @State private var transferRequest: GalleryTransferRequest?
    @State private var pendingTransferData: Data?
    @State private var pendingTransferImage: UIImage?

    init(photos: [GalleryPhoto], initialIndex: Int, onTransferToDevice: @escaping (Data) -> Void) {
        self.photos = photos
        self.initialIndex = initialIndex
        self.onTransferToDevice = onTransferToDevice
        _selectedIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        let buttonTextColor = Color.white
        let buttonFillColor = colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)
        let secondaryTextColor = colorScheme == .dark ? Color.white.opacity(0.82) : Color.black.opacity(0.72)
        let primaryButtonFillColor = Color(red: 0.0, green: 0.48, blue: 1.0)

        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color.black : Color.white)
                    .ignoresSafeArea()

                devicePreview

                VStack {
                    Spacer()

                    VStack(spacing: 10) {
                        transferStatusView

                        Button(action: transferSelectedPhotoDirectly) {
                            Text("传输到设备")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(buttonTextColor)
                                .padding(.horizontal, 18)
                                .frame(height: 38)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(primaryButtonFillColor)
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(primaryButtonFillColor.opacity(0.16), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(activeDevice == nil || isTransferInProgress)

                        Button(action: openManualAdjustment) {
                            Text("手动调整")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(secondaryTextColor)
                                .padding(.horizontal, 16)
                                .frame(height: 36)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(buttonFillColor.opacity(0.72))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isTransferInProgress)
                    }
                    .padding(.bottom, 10)
                    .offset(y: 20)
                }
            }
            .sheet(item: $transferRequest) { request in
                TransferSheetView(
                    sourceImage: request.photo.image,
                    title: request.photo.title,
                    onTransferSucceeded: {
                        onTransferToDevice(request.photo.imageData)
                        dismiss()
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
                    Text(photos[selectedIndex].title)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
        }
    }

    @ViewBuilder
    private var transferStatusView: some View {
        if isTransferInProgress {
            ProgressView(value: bleService.transferProgress)
                .frame(width: 150)
        } else if case .failed = bleService.transferPhase, let errorMessage = bleService.errorMessage {
            Text(errorMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private func transferSelectedPhotoDirectly() {
        guard let device = activeDevice else { return }

        let photo = photos[selectedIndex]
        let transferImage = defaultTransferImage(from: photo.image, device: device)
        let displayImage = defaultDisplayImage(from: photo.image, device: device)
        pendingTransferData = photo.imageData
        pendingTransferImage = displayImage
        bleService.transfer(image: transferImage, to: device)
    }

    private func openManualAdjustment() {
        pendingTransferData = nil
        pendingTransferImage = nil
        transferRequest = GalleryTransferRequest(photo: photos[selectedIndex])
    }

    private func defaultTransferImage(from image: UIImage, device: BleDevice) -> UIImage {
        EInkImageRenderer.renderForTransfer(
            image: image,
            targetSize: device.profile.pixelSize,
            fitMode: .centerCrop,
            adjustment: .default,
            profile: device.profile
        )
    }

    private func defaultDisplayImage(from image: UIImage, device: BleDevice) -> UIImage {
        EInkImageRenderer.render(
            image: image,
            targetSize: device.profile.pixelSize,
            fitMode: .centerCrop,
            adjustment: .default
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
                    GeometryReader { proxy in
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    }
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
