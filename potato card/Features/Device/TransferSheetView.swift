import SwiftUI
import UIKit

struct TransferSheetView: View {
    let sourceImage: UIImage
    let title: String
    var editStateKey: TransferEditStateKey? = nil
    var onTransferSucceeded: (() -> Void)?

    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var adjustment = EInkManualAdjustment.default
    @State private var selectedDitherAlgorithm: EInkDitherAlgorithm = .floydSteinberg
    @State private var didLoadInitialState = false
    @State private var isAlgorithmExpanded = false

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        previewSection
                        adjustmentSection
                        algorithmSection
                        transferSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
            }
            .navigationTitle(title)
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

                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        saveEditStateIfNeeded()
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .disabled(editStateKey == nil || bleService.transferPhase == .transferring || bleService.transferPhase == .preparing)
                }
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

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("预览")

            EInkDevicePreview(
                sourceImage: sourceImage,
                fitMode: .manual,
                adjustment: adjustment,
                renderTargetSize: renderTargetSize
            )
                .frame(maxWidth: .infinity)
                .frame(height: 330)
        }
    }

    private var transferSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if case .failed = bleService.transferPhase, let errorMessage = bleService.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
            }

            if bleService.transferPhase == .transferring || bleService.transferPhase == .preparing {
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
            .disabled(activeDevice == nil || bleService.transferPhase == .transferring || bleService.transferPhase == .preparing)
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
        .disabled(bleService.transferPhase == .transferring || bleService.transferPhase == .preparing)
    }

    private var adjustmentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("手动调整")

            adjustmentSlider(title: "缩放", value: $adjustment.scale, range: 0.25...3)
            adjustmentSlider(title: "水平", value: $adjustment.offsetX, range: -160...160)
            adjustmentSlider(title: "垂直", value: $adjustment.offsetY, range: -160...160)

            Button {
                adjustment = .default
                // 重置后立即清除持久化状态，这样即使用户不点保存、直接关闭面板，
                // 一级页面上的“手动调整”黄色标记也能同步恢复原状。
                if let editStateKey {
                    TransferEditStateStore.delete(for: editStateKey)
                }
            } label: {
                Label("重置", systemImage: "arrow.counterclockwise")
            }
            .font(.system(size: 14, weight: .semibold))
        }
    }

    private func adjustmentSlider(title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(primaryTextColor)

            Slider(value: value, in: range)
        }
    }

    private func loadInitialStateIfNeeded() {
        guard !didLoadInitialState else { return }
        didLoadInitialState = true
        selectedDitherAlgorithm = bleService.ditherAlgorithm

        guard let editStateKey, let savedAdjustment = TransferEditStateStore.load(for: editStateKey) else { return }
        // 单图只恢复缩放和偏移，图像算法仍然走全局设置。
        adjustment = savedAdjustment
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(primaryTextColor)
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

private struct EInkDevicePreview: View {
    let sourceImage: UIImage
    let fitMode: EInkImageFitMode
    let adjustment: EInkManualAdjustment
    let renderTargetSize: CGSize

    var body: some View {
        ZStack {
            Image("ink_tatoo2")
                .resizable()
                .scaledToFit()
                .frame(width: 230, height: 310)

            deviceScreenPreview
                .frame(width: 164, height: 245)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .offset(y: -22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deviceScreenPreview: some View {
        GeometryReader { proxy in
            let drawRect = previewDrawRect(in: proxy.size)

            Image(uiImage: sourceImage)
                .resizable()
                .interpolation(.medium)
                .frame(width: drawRect.width, height: drawRect.height)
                .position(x: drawRect.midX, y: drawRect.midY)
        }
        .background(Color.white)
        .clipped()
    }

    private func previewDrawRect(in targetSize: CGSize) -> CGRect {
        let imageSize = sourceImage.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: targetSize)
        }

        let baseScale = max(targetSize.width / imageSize.width, targetSize.height / imageSize.height)
        let manualScale = fitMode == .manual ? adjustment.scale : 1
        let finalSize = CGSize(
            width: imageSize.width * baseScale * manualScale,
            height: imageSize.height * baseScale * manualScale
        )

        let offsetScale = min(targetSize.width / renderTargetSize.width, targetSize.height / renderTargetSize.height)
        let offset = fitMode == .manual
            ? CGSize(width: adjustment.offsetX * offsetScale, height: adjustment.offsetY * offsetScale)
            : .zero

        let origin = CGPoint(
            x: (targetSize.width - finalSize.width) / 2 + offset.width,
            y: (targetSize.height - finalSize.height) / 2 + offset.height
        )

        return CGRect(origin: origin, size: finalSize)
    }
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
