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
            // 整体改用 Form + 分组样式，与系统“设置 / 照片”等编辑面板一致，
            // 自动跟随暗色模式、动态字体与无障碍设置，不再手写一套配色。
            Form {
                Section {
                    interactivePreview
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                adjustmentSection
                algorithmSection
            }
            .formStyle(.grouped)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // iOS 26 标准“主操作浮动底栏”模式：背景走系统 .bar 材质，
                // 主按钮使用 borderedProminent + 子胶囊形状，填满安全区并保留底部 padding。
                bottomActionBar
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
                    .fontWeight(.semibold)
                    .disabled(editStateKey == nil || isTransferInProgress)
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
            .onChange(of: bleService.transferPhase) { phase in
                if phase == .succeeded {
                    saveEditStateIfNeeded()
                    bleService.markLastTransferredImage(displayImage)
                    onTransferSucceeded?()
                    dismiss()
                }
            }
        }
    }

    // MARK: - Toolbar Title

    // 顶部标题栏：标题 + 编辑图标。只有调用方传入 onRename 时才显示笔形图标。
    private var titleBar: some View {
        HStack(spacing: 4) {
            Text(displayTitle)
                .font(.headline)
                .lineLimit(1)

            if onRename != nil {
                Button("修改名称", systemImage: "pencil") {
                    renameDraft = displayTitle
                    isRenaming = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .accessibilityLabel("修改图片名称")
            }
        }
    }

    // MARK: - Preview

    // 上方的“土豆片”预览：支持双指缩放、旋转、单/双指拖动；变化实时反馈到下方滑动条。
    private var interactivePreview: some View {
        InteractiveDevicePreview(
            sourceImage: sourceImage,
            adjustment: $adjustment,
            renderTargetSize: renderTargetSize,
            isInteractive: !isTransferInProgress
        )
    }

    // MARK: - Manual Adjustment Section

    // 用原生 DisclosureGroup 替换之前的 Button + chevron 自绘组合，跟随系统的展开动画与暗色模式。
    // 重置图标内嵌在 label 右侧，仅在非默认状态显示。
    private var adjustmentSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isAdjustmentExpanded) {
                sliderRow(title: "缩放", value: $adjustment.scale, range: 0.25...3, format: scalePercent)
                sliderRow(title: "旋转", value: $adjustment.rotation, range: -.pi...(.pi), format: rotationDegrees)
                sliderRow(title: "水平", value: $adjustment.offsetX, range: -160...160, format: offsetText)
                sliderRow(title: "垂直", value: $adjustment.offsetY, range: -160...160, format: offsetText)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("手动调整")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(adjustmentSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if adjustment != .default {
                        Button("重置", systemImage: "arrow.counterclockwise", action: resetAdjustment)
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("重置手动调整")
                            .disabled(isTransferInProgress)
                    }
                }
            }
        }
    }

    // MARK: - Algorithm Section

    private var algorithmSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isAlgorithmExpanded) {
                ForEach(EInkDitherAlgorithm.allCases) { algorithm in
                    algorithmRow(algorithm)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("全局图像算法")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(selectedDitherAlgorithm.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func algorithmRow(_ algorithm: EInkDitherAlgorithm) -> some View {
        Button {
            selectedDitherAlgorithm = algorithm
            bleService.setDitherAlgorithm(algorithm)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(algorithm.title)
                        .foregroundStyle(.primary)
                    Text(algorithm.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selectedDitherAlgorithm == algorithm {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isTransferInProgress)
    }

    // MARK: - Bottom Action Bar

    // 浮动底栏：状态 / 进度 上方顯示，下方是主按钮。
    // 参考 iOS 26 “邮箱 / 提醒事项 / 预订设备”面板的主操作样式。
    private var bottomActionBar: some View {
        VStack(spacing: 10) {
            if case .failed = bleService.transferPhase, let errorMessage = bleService.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                guard !isTransferInProgress, let device = activeDevice else { return }
                // 点击主按钮同时完成“保存 + 传输”，即使传输中途失败也能保留调整。
                saveEditStateIfNeeded()
                bleService.transfer(
                    image: transferImage,
                    displayImage: displayImage,
                    to: device,
                    algorithm: selectedDitherAlgorithm
                )
            } label: {
                TransferProgressButtonLabel(
                    title: "保存并传输到设备",
                    progressTitle: transferButtonProgressTitle,
                    progress: bleService.transferProgress,
                    isInProgress: isTransferInProgress,
                    height: 50,
                    cornerRadius: 25
                )
            }
            .buttonStyle(.plain)
            .disabled(activeDevice == nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: - Slider Row

    private func sliderRow(
        title: String,
        value: Binding<CGFloat>,
        range: ClosedRange<CGFloat>,
        format: (CGFloat) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(title) {
                Text(format(value.wrappedValue))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            Slider(value: value, in: range)
                .disabled(isTransferInProgress)
        }
    }

    // MARK: - Helpers

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
            return "保存并传输到设备"
        }
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
}

struct TransferProgressButtonLabel: View {
    let title: String
    let progressTitle: String
    let progress: Double
    let isInProgress: Bool
    var width: CGFloat? = nil
    let height: CGFloat
    let cornerRadius: CGFloat
    var accentColor = Color(red: 0.0, green: 0.48, blue: 1.0)

    private var clampedProgress: CGFloat {
        CGFloat(min(1, max(0, progress)))
    }

    private var showsProgressFill: Bool {
        isInProgress && clampedProgress >= 0.03
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isInProgress ? accentColor.opacity(0.28) : accentColor)

            if showsProgressFill {
                GeometryReader { proxy in
                    // 传输中用按钮内部进度填充，外层低透明度底色就是灰色蒙层效果。
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(accentColor)
                        .frame(width: min(proxy.size.width, max(height, proxy.size.width * clampedProgress)))
                }
                .allowsHitTesting(false)
            }

            Text(isInProgress ? progressTitle : title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(accentColor.opacity(isInProgress ? 0.10 : 0.16), lineWidth: 1)
        )
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
