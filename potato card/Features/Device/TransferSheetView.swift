import SwiftUI
import UIKit

struct TransferSheetView: View {
    let sourceImage: UIImage
    let title: String
    var editStateKey: TransferEditStateKey? = nil
    var onTransferSucceeded: (() -> Void)?
    // 仅在调用方支持改名时（图库）才会传入；为 nil 时隐藏标题旁的编辑图标。
    var onRename: ((String) -> Void)? = nil

    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var adjustment = EInkManualAdjustment.default
    @State private var selectedDitherAlgorithm: EInkDitherAlgorithm = .floydSteinberg
    @State private var didLoadInitialState = false
    @State private var isAlgorithmExpanded = false
    @State private var isAdjustmentExpanded = false
    @State private var displayTitle: String
    @State private var isRenaming = false
    @State private var renameDraft = ""

    init(
        sourceImage: UIImage,
        title: String,
        editStateKey: TransferEditStateKey? = nil,
        onTransferSucceeded: (() -> Void)? = nil,
        onRename: ((String) -> Void)? = nil
    ) {
        self.sourceImage = sourceImage
        self.title = title
        self.editStateKey = editStateKey
        self.onTransferSucceeded = onTransferSucceeded
        self.onRename = onRename
        _displayTitle = State(initialValue: title)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        interactivePreview
                        adjustmentSection
                        algorithmSection
                        transferSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadInitialStateIfNeeded()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .principal) {
                    titleBar
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        saveEditStateIfNeeded()
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .disabled(editStateKey == nil || bleService.transferPhase == .transferring || bleService.transferPhase == .preparing)
                }
            }
            .alert("修改图片名称", isPresented: $isRenaming) {
                TextField("名称", text: $renameDraft)
                Button("取消", role: .cancel) {}
                Button("保存") {
                    let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, trimmed != displayTitle else { return }
                    displayTitle = trimmed
                    onRename?(trimmed)
                }
            } message: {
                Text("仅修改这张照片的显示名称。")
            }
            .onChange(of: bleService.transferPhase) { _, phase in
                if phase == .succeeded {
                    saveEditStateIfNeeded()
                    bleService.markLastTransferredImage(displayImage)
                    onTransferSucceeded?()
                    dismiss()
                }
            }
        }
    }

    // 顶部标题栏：标题 + 编辑图标。只有调用方传入 onRename 时才显示笔形图标。
    private var titleBar: some View {
        HStack(spacing: 6) {
            Text(displayTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)

            if onRename != nil {
                Button {
                    renameDraft = displayTitle
                    isRenaming = true
                } label: {
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("修改图片名称")
            }
        }
    }

    // 上方的“土豆片”预览：支持双指缩放、旋转、单/双指拖动；变化实时反馈到下方的滑动条。
    // 不再单独占一个 “预览” section header，让整个面板视觉更紧凑。
    private var interactivePreview: some View {
        InteractiveDevicePreview(
            sourceImage: sourceImage,
            adjustment: $adjustment,
            renderTargetSize: renderTargetSize,
            isInteractive: !isTransferInProgress
        )
        .frame(maxWidth: .infinity)
        .frame(height: 330)
    }

    private var transferSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .failed = bleService.transferPhase, let errorMessage = bleService.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
            }

            if isTransferInProgress {
                ProgressView(value: bleService.transferProgress)
                Text("\(bleService.transferPhase.title) \(Int(bleService.transferProgress * 100))%")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
            }

            Button {
                guard let device = activeDevice else { return }
                // 点击下方按钮同时完成“保存 + 传输”，即使传输中途失败也能保留调整。
                saveEditStateIfNeeded()
                bleService.transfer(
                    image: transferImage,
                    displayImage: displayImage,
                    to: device,
                    algorithm: selectedDitherAlgorithm
                )
            } label: {
                Label("保存并传输到设备", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(activeDevice == nil || isTransferInProgress)
        }
    }

    private var algorithmSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    isAlgorithmExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("图像算法")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(primaryTextColor)

                        Text(selectedDitherAlgorithm.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                    }

                    Spacer()

                    Image(systemName: isAlgorithmExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                }
            }
            .buttonStyle(.plain)

            if isAlgorithmExpanded {
                VStack(spacing: 8) {
                    ForEach(EInkDitherAlgorithm.allCases) { algorithm in
                        algorithmRow(algorithm)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func algorithmRow(_ algorithm: EInkDitherAlgorithm) -> some View {
        Button {
            selectedDitherAlgorithm = algorithm
            bleService.setDitherAlgorithm(algorithm)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(algorithm.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(primaryTextColor)

                    Text(algorithm.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if selectedDitherAlgorithm == algorithm {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accentColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selectedDitherAlgorithm == algorithm ? selectedAlgorithmFillColor : rowFillColor)
            )
        }
        .buttonStyle(.plain)
        .disabled(isTransferInProgress)
    }

    // 手动调整改造为可折叠的下拉菜单，结构和图像算法保持一致；重置按钮放进展开后的 header 行。
    private var adjustmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        isAdjustmentExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("手动调整")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(primaryTextColor)

                            Text(adjustmentSummary)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(secondaryTextColor)
                        }

                        Spacer()

                        Image(systemName: isAdjustmentExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(secondaryTextColor)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // 仅当存在非默认调整时显示重置图标，避免 header 上挂着无意义的按钮。
                if adjustment != .default {
                    Button(action: resetAdjustment) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(secondaryTextColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("重置手动调整")
                    .disabled(isTransferInProgress)
                }
            }

            if isAdjustmentExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    adjustmentSlider(title: "缩放", value: $adjustment.scale, range: 0.25...3, format: scalePercent)
                    adjustmentSlider(title: "旋转", value: $adjustment.rotation, range: -.pi...(.pi), format: rotationDegrees)
                    adjustmentSlider(title: "水平", value: $adjustment.offsetX, range: -160...160, format: offsetText)
                    adjustmentSlider(title: "垂直", value: $adjustment.offsetY, range: -160...160, format: offsetText)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func adjustmentSlider(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        format: (CGFloat) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(primaryTextColor)

                Spacer()

                Text(format(value.wrappedValue))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(secondaryTextColor)
            }

            Slider(value: value, in: range)
                .disabled(isTransferInProgress)
        }
    }

    private func resetAdjustment() {
        withAnimation(.easeOut(duration: 0.2)) {
            adjustment = .default
        }
        // 重置后立即清除持久化状态，这样即使用户不点保存、直接关闭面板，
        // 一级页面上的“手动调整”黄色标记也能同步恢复原状。
        if let editStateKey {
            TransferEditStateStore.delete(for: editStateKey)
        }
    }

    private func loadInitialStateIfNeeded() {
        guard !didLoadInitialState else { return }
        didLoadInitialState = true
        selectedDitherAlgorithm = bleService.ditherAlgorithm

        guard let editStateKey, let savedAdjustment = TransferEditStateStore.load(for: editStateKey) else { return }
        // 单图只恢复缩放和偏移，图像算法仍然走全局设置。
        adjustment = savedAdjustment
        // 已经有调整记录的图直接展开手动调整面板，让用户一眼看到状态。
        isAdjustmentExpanded = savedAdjustment != .default
    }

    private func saveEditStateIfNeeded() {
        guard let editStateKey else { return }
        // 默认值不需要持久化，直接删除记录，避免一级页面“黄色”标记误点亮。
        if adjustment == .default {
            TransferEditStateStore.delete(for: editStateKey)
        } else {
            TransferEditStateStore.save(adjustment, for: editStateKey)
        }
    }

    // 折叠状态下显示的简要描述，让用户不展开也能知道当前调整。
    private var adjustmentSummary: String {
        if adjustment == .default {
            return "未调整"
        }
        let parts: [String] = [
            scalePercent(adjustment.scale),
            rotationDegrees(adjustment.rotation),
            offsetText(adjustment.offsetX) + " / " + offsetText(adjustment.offsetY)
        ]
        return parts.joined(separator: " · ")
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

    private var isTransferInProgress: Bool {
        bleService.transferPhase == .transferring || bleService.transferPhase == .preparing
    }

    private var displayImage: UIImage {
        EInkImageRenderer.render(
            image: sourceImage,
            targetSize: renderTargetSize,
            fitMode: .manual,
            adjustment: adjustment
        )
    }

    private var transferImage: UIImage {
        let profile = activeDevice?.profile ?? EInkDeviceProfile.fallback
        return EInkImageRenderer.renderForTransfer(
            image: sourceImage,
            targetSize: profile.pixelSize,
            fitMode: .manual,
            adjustment: adjustment,
            profile: profile,
            ditherAlgorithm: selectedDitherAlgorithm
        )
    }

    private var renderTargetSize: CGSize {
        activeDevice?.profile.pixelSize ?? EInkDeviceProfile.fallback.pixelSize
    }

    private var activeDevice: BleDevice? {
        bleService.connectedDevice ?? bleService.selectedDevice
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.07, green: 0.07, blue: 0.08) : .white
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.92)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.48)
    }

    private var rowFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.045)
    }

    private var selectedAlgorithmFillColor: Color {
        colorScheme == .dark ? accentColor.opacity(0.18) : accentColor.opacity(0.10)
    }

    private var accentColor: Color {
        Color(red: 0.18, green: 0.49, blue: 0.98)
    }

}

// 上方的“土豆片”支持触控交互的预览：一指/双指拖动 = 偏移，双指捏合 = 缩放，双指旋转 = 旋转。
// 这些手势都用 .gesture 而不是 simultaneousGesture，确保触发时不会抢占 sheet 自身的下滑关闭手势——
// 下滑关闭由 NavigationStack 的标题栏 / .presentationDragIndicator 区域处理，跟交互区互不冲突。
private struct InteractiveDevicePreview: View {
    let sourceImage: UIImage
    @Binding var adjustment: EInkManualAdjustment
    let renderTargetSize: CGSize
    var isInteractive: Bool = true

    @State private var gestureScaleStart: CGFloat = 1
    @State private var gestureRotationStart: CGFloat = 0
    @State private var gestureOffsetStart: CGSize = .zero

    var body: some View {
        ZStack {
            Image("ink_tatoo2")
                .resizable()
                .scaledToFit()
                .frame(width: 230, height: 310)
                .allowsHitTesting(false)

            screen
                .frame(width: 164, height: 245)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .offset(y: -22)
                .gesture(isInteractive ? combinedGesture : nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var screen: some View {
        GeometryReader { proxy in
            // 在屏幕中心对图片做缩放 + 旋转 + 偏移；几何与 EInkImageRenderer 的 drawRect 公式同步。
            let baseScale = max(proxy.size.width / sourceImage.size.width, proxy.size.height / sourceImage.size.height)
            let offsetScale = min(proxy.size.width / renderTargetSize.width, proxy.size.height / renderTargetSize.height)

            Image(uiImage: sourceImage)
                .resizable()
                .interpolation(.medium)
                .frame(width: sourceImage.size.width * baseScale, height: sourceImage.size.height * baseScale)
                .scaleEffect(adjustment.scale)
                .rotationEffect(.radians(Double(adjustment.rotation)))
                .offset(x: adjustment.offsetX * offsetScale, y: adjustment.offsetY * offsetScale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color.white)
        .clipped()
        .contentShape(Rectangle())
    }

    private var combinedGesture: some Gesture {
        let drag = DragGesture()
            .onChanged { value in
                adjustment.offsetX = clampOffset(gestureOffsetStart.width + value.translation.width)
                adjustment.offsetY = clampOffset(gestureOffsetStart.height + value.translation.height)
            }
            .onEnded { _ in
                gestureOffsetStart = CGSize(width: adjustment.offsetX, height: adjustment.offsetY)
            }

        let magnify = MagnificationGesture()
            .onChanged { value in
                adjustment.scale = clampScale(gestureScaleStart * value)
            }
            .onEnded { _ in
                gestureScaleStart = adjustment.scale
            }

        let rotate = RotationGesture()
            .onChanged { angle in
                adjustment.rotation = clampRotation(gestureRotationStart + CGFloat(angle.radians))
            }
            .onEnded { _ in
                gestureRotationStart = adjustment.rotation
            }

        // 双指 + 单指手势同时识别，跟系统照片的编辑面板交互一致。
        return SimultaneousGesture(
            SimultaneousGesture(magnify, rotate),
            drag
        )
        .onChanged { _ in
            // 第一次触发时把当前值快照下来，作为后续累加的基线。
            if gestureOffsetStart == .zero, adjustment.offsetX == 0, adjustment.offsetY == 0 {
                gestureOffsetStart = .zero
            }
        }
    }

    private func clampScale(_ value: CGFloat) -> CGFloat { min(max(value, 0.25), 3) }
    private func clampOffset(_ value: CGFloat) -> CGFloat { min(max(value, -160), 160) }
    private func clampRotation(_ value: CGFloat) -> CGFloat { min(max(value, -.pi), .pi) }
}

private struct TransferSheetView_Previews: PreviewProvider {
    static var previews: some View {
        TransferSheetView(
            sourceImage: UIImage(named: "tatoo1") ?? UIImage.previewFallbackImage(),
            title: "传输预览"
        )
        .environmentObject(BleTransferService())
    }
}

private extension UIImage {
    static func previewFallbackImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800))
        return renderer.image { context in
            UIColor.systemGray6.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))

            UIColor.systemGray3.setFill()
            context.fill(CGRect(x: 140, y: 180, width: 320, height: 440))
        }
    }
}
