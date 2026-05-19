//
//  AlbumView.swift
//  potato card
//

import SwiftUI
import UIKit

enum AlbumCatalog {
    static let jayAlbums: [String] = [
        "范特西",
        "八度空間",
        "葉惠美",
        "七里香",
        "11月的蕭邦",
        "依然范特西",
        "我很忙",
        "魔杰座",
        "跨時代",
        "驚嘆號",
        "十二新作",
        "周杰倫的床邊故事",
        "最伟大的作品"
    ]

    static let stefanieAlbums: [String] = [
        "孙燕姿",
        "我要的幸福",
        "风筝",
        "Start自选集",
        "The Moment",
        "完美的一天",
        "逆光",
        "跳舞的梵谷",
        "是时候",
        "克卜勒",
        "彩虹金刚",
        "未完成",
        "Leave"
    ]

    static var allAlbums: [String] {
        jayAlbums + stefanieAlbums
    }

    static var featuredAlbums: [String] {
        ["范特西", "七里香", "孙燕姿"]
    }
}

struct AlbumView: View {
    let onTransferToDevice: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedAlbum: SelectedAlbumGroup?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("专辑")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(primaryTextColor)

            artistSection(title: "周杰伦", albums: AlbumCatalog.jayAlbums)
            artistSection(title: "孙燕姿", albums: AlbumCatalog.stefanieAlbums)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $selectedAlbum) { group in
            AlbumImageViewer(
                albums: group.albums,
                initialIndex: group.initialIndex,
                onTransferToDevice: onTransferToDevice
            )
            // detent / dragIndicator 都由 AlbumImageViewer 内部声明，
            // 编辑模式会在 .height(560) 和 .large 之间切换。
        }
    }

    private func artistSection(title: String, albums: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryTextColor)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(Array(albums.enumerated()), id: \.element) { index, album in
                        albumCard(album, albums: albums, index: index)
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.horizontal, -24)
        }
    }

    private func albumCard(_ album: String, albums: [String], index: Int) -> some View {
        Button {
            selectedAlbum = SelectedAlbumGroup(albums: albums, initialIndex: index)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(album)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 148, height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                    )

                Text(album)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(2)
            }
            .frame(width: 148, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.92)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06)
    }
}

private struct SelectedAlbumGroup: Identifiable {
    let id: String
    let albums: [String]
    let initialIndex: Int

    init(albums: [String], initialIndex: Int) {
        self.albums = albums
        self.initialIndex = initialIndex
        self.id = "\(albums.joined(separator: "|"))-\(initialIndex)"
    }
}

private struct AlbumImageViewer: View {
    let albums: [String]
    let initialIndex: Int
    let onTransferToDevice: (String) -> Void
    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedIndex: Int
    @State private var pendingTransferAlbum: String?
    @State private var pendingTransferImage: UIImage?
    // 与 GalleryImageViewer 同款：编辑状态由 sheet 高度驱动。
    // .large = 全屏编辑，.height(560) = 预览。
    @State private var selectedDetent: PresentationDetent = .height(560)
    @State private var draftAdjustment = EInkManualAdjustment.default
    @State private var gestureScaleStart: CGFloat = 1
    @State private var gestureRotationStart: CGFloat = 0
    @State private var gestureOffsetStart: CGSize = .zero

    private var isExpanded: Bool { selectedDetent == .large }

    init(albums: [String], initialIndex: Int, onTransferToDevice: @escaping (String) -> Void) {
        self.albums = albums
        self.initialIndex = initialIndex
        self.onTransferToDevice = onTransferToDevice
        _selectedIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topPreviewSection
                    .frame(maxWidth: .infinity)
                    .frame(height: 352)

                bottomScrollSection
            }
            .background((colorScheme == .dark ? Color.black : Color.white).ignoresSafeArea())
            .onChange(of: selectedIndex) { _ in
                draftAdjustment = savedAdjustmentForCurrentAlbum()
                resetGestureBaselines()
            }
            .onAppear {
                draftAdjustment = savedAdjustmentForCurrentAlbum()
                resetGestureBaselines()
            }
            .onChange(of: isExpanded) { expanded in
                if !expanded {
                    persistDraftIfNeeded()
                } else {
                    resetGestureBaselines()
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            }
            .onChange(of: bleService.transferPhase) { phase in
                guard phase == .succeeded, let album = pendingTransferAlbum else { return }
                if let pendingTransferImage {
                    bleService.markLastTransferredImage(pendingTransferImage)
                }
                onTransferToDevice(album)
                pendingTransferAlbum = nil
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
                    Text(albums[selectedIndex])
                        .font(.system(size: 17, weight: .semibold))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if isExpanded {
                        Button("完成") {
                            collapseToPreview()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .presentationDetents([.height(560), .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    // MARK: - Layout

    private var topPreviewSection: some View {
        ZStack {
            albumFramedPreview
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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

    private var primaryControls: some View {
        VStack(spacing: 10) {
            transferStatusView

            Button(action: transferSelectedAlbumDirectly) {
                transferButtonLabel
            }
            .buttonStyle(.plain)
            .disabled(activeDevice == nil)

            Button {
                if isExpanded {
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
            .tint(currentAlbumIsCustomized || draftAdjustment != .default ? .yellow : .secondary)
            .disabled(isTransferInProgress)
        }
    }

    private var adjustmentSection: some View {
        VStack(spacing: 0) {
            sliderRow(title: "缩放", value: $draftAdjustment.scale, range: 0.25...3, format: scalePercent)
            Divider().padding(.leading, 72)
            sliderRow(title: "旋转", value: $draftAdjustment.rotation, range: -.pi...(.pi), format: rotationDegrees)
            Divider().padding(.leading, 72)
            sliderRow(title: "水平", value: $draftAdjustment.offsetX, range: -160...160, format: offsetText)
            Divider().padding(.leading, 72)
            sliderRow(title: "垂直", value: $draftAdjustment.offsetY, range: -160...160, format: offsetText)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var transferStatusView: some View {
        if case .failed = bleService.transferPhase, let errorMessage = bleService.errorMessage {
            Text(errorMessage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private func transferSelectedAlbumDirectly() {
        guard
            !isTransferInProgress,
            let device = activeDevice,
            let image = UIImage(named: albums[selectedIndex])
        else {
            return
        }

        // 走与 GalleryImageViewer 同款的「读取保存调整」逻辑：用户编辑保存后，
        // 后续点「传输到设备」自动应用，无需再次编辑。
        let savedAdjustment = TransferEditStateStore.load(for: .album(albums[selectedIndex]))
        let adjustment = savedAdjustment ?? .default
        let fitMode: EInkImageFitMode = (savedAdjustment != nil && adjustment != .default) ? .manual : .centerCrop

        let transferImage = EInkImageRenderer.renderForTransfer(
            image: image,
            targetSize: device.profile.pixelSize,
            fitMode: fitMode,
            adjustment: adjustment,
            profile: device.profile,
            ditherAlgorithm: bleService.ditherAlgorithm
        )
        let displayImage = EInkImageRenderer.render(
            image: image,
            targetSize: device.profile.pixelSize,
            fitMode: fitMode,
            adjustment: adjustment
        )
        pendingTransferAlbum = albums[selectedIndex]
        pendingTransferImage = displayImage
        bleService.transfer(image: transferImage, displayImage: displayImage, to: device)
    }

    // MARK: - Bottom layout

    private func sliderRow(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        format: @escaping (CGFloat) -> String
    ) -> some View {
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

    // MARK: - Edit helpers

    private func savedAdjustmentForCurrentAlbum() -> EInkManualAdjustment {
        TransferEditStateStore.load(for: .album(albums[selectedIndex])) ?? .default
    }

    private var currentAlbumIsCustomized: Bool {
        guard albums.indices.contains(selectedIndex) else { return false }
        let key = TransferEditStateKey.album(albums[selectedIndex])
        guard let saved = TransferEditStateStore.load(for: key) else { return false }
        return saved != .default
    }

    private func enterEditMode() {
        guard !isTransferInProgress else { return }
        draftAdjustment = savedAdjustmentForCurrentAlbum()
        resetGestureBaselines()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
            selectedDetent = .large
        }
    }

    private func expandToEdit() { enterEditMode() }

    private func collapseToPreview() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.84)) {
            selectedDetent = .height(560)
        }
    }

    private func persistDraftIfNeeded() {
        let key = TransferEditStateKey.album(albums[selectedIndex])
        if draftAdjustment == .default {
            TransferEditStateStore.delete(for: key)
        } else {
            TransferEditStateStore.save(draftAdjustment, for: key)
        }
    }

    private func resetGestureBaselines() {
        gestureScaleStart = draftAdjustment.scale
        gestureRotationStart = draftAdjustment.rotation
        gestureOffsetStart = CGSize(width: draftAdjustment.offsetX, height: draftAdjustment.offsetY)
    }

    private var activeDevice: BleDevice? {
        bleService.connectedDevice ?? bleService.selectedDevice
    }

    private var isTransferInProgress: Bool {
        bleService.transferPhase == .preparing || bleService.transferPhase == .transferring
    }

    private var primaryTransferButtonFillColor: Color {
        Color(red: 0.0, green: 0.48, blue: 1.0)
    }

    private var transferProgressPercent: Int {
        min(100, max(0, Int((bleService.transferProgress * 100).rounded())))
    }

    private var transferButtonProgressTitle: String {
        switch bleService.transferPhase {
        case .preparing:
            return "等待 \(transferProgressPercent)%"
        case .transferring:
            return "传输中 \(transferProgressPercent)%"
        default:
            return "传输到设备"
        }
    }

    private var transferButtonLabel: some View {
        TransferProgressButtonLabel(
            title: "传输到设备",
            progressTitle: transferButtonProgressTitle,
            progress: bleService.transferProgress,
            isInProgress: isTransferInProgress,
            width: 140,
            height: 38,
            cornerRadius: 19,
            accentColor: primaryTransferButtonFillColor
        )
    }

    private var albumFramedPreview: some View {
        ZStack {
            if isExpanded, let image = UIImage(named: albums[selectedIndex]) {
                editableScreen(for: image)
                    .frame(width: 186, height: 280)
                    .mask(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .frame(width: 186, height: 280)
                    )
                    .offset(y: -19)
            } else {
                TabView(selection: $selectedIndex) {
                    ForEach(Array(albums.enumerated()), id: \.offset) { index, album in
                        albumScreenImage(album)
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
        // 去掉之前的 .offset(y: -60)：VStack 布局下它会让灯柝顶逿进 nav bar 区域，
        // 看起来像预览顶多了一条白条。
    }

    // 编辑模式下的可交互预览，几何与 EInkImageRenderer 同步，
    // 用户看到的就是后续传输到设备实际呈现的画面。
    @ViewBuilder
    private func editableScreen(for image: UIImage) -> some View {
        let renderTargetSize = activeDevice?.profile.pixelSize ?? EInkDeviceProfile.fallback.pixelSize
        GeometryReader { proxy in
            let baseScale = max(proxy.size.width / image.size.width, proxy.size.height / image.size.height)
            let offsetScale = min(proxy.size.width / renderTargetSize.width, proxy.size.height / renderTargetSize.height)

            Image(uiImage: image)
                .resizable()
                .interpolation(.medium)
                .frame(width: image.size.width * baseScale, height: image.size.height * baseScale)
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

    // 「土豆片屏幕」内的非编辑模式预览，应用已保存的调整。
    private func albumScreenImage(_ album: String) -> some View {
        let savedAdjustment = TransferEditStateStore.load(for: .album(album)) ?? .default
        let renderTargetSize = activeDevice?.profile.pixelSize ?? EInkDeviceProfile.fallback.pixelSize
        return GeometryReader { proxy in
            if let image = UIImage(named: album) {
                if savedAdjustment == .default {
                    Image(album)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    let baseScale = max(proxy.size.width / image.size.width, proxy.size.height / image.size.height)
                    let offsetScale = min(proxy.size.width / renderTargetSize.width, proxy.size.height / renderTargetSize.height)
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.medium)
                        .frame(width: image.size.width * baseScale, height: image.size.height * baseScale)
                        .scaleEffect(savedAdjustment.scale)
                        .rotationEffect(.radians(Double(savedAdjustment.rotation)))
                        .offset(x: savedAdjustment.offsetX * offsetScale, y: savedAdjustment.offsetY * offsetScale)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .background(Color.white)
                        .clipped()
                }
            }
        }
        .frame(width: 186, height: 280)
    }

    // 不再需要自定义上滑手势：sheet 原生的 detent 拖动就是「进入全屏编辑」入口。

}

private struct AlbumView_Previews: PreviewProvider {
    static var previews: some View {
        AlbumView(onTransferToDevice: { _ in })
            .environmentObject(BleTransferService())
    }
}
