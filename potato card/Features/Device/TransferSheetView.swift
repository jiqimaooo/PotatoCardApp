import SwiftUI
import UIKit

struct TransferSheetView: View {
    let sourceImage: UIImage
    let title: String
    var onTransferSucceeded: (() -> Void)?

    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var adjustment = EInkManualAdjustment.default

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        previewSection
                        adjustmentSection
                        transferSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .onChange(of: bleService.transferPhase) { _, phase in
                if phase == .succeeded {
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
            sectionHeader("传输")

            if let device = activeDevice, device.profile.isFallback {
                Text("未知型号，使用默认尺寸 \(device.profile.displaySize)。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
            }

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
                bleService.transfer(image: transferImage, to: device)
            } label: {
                Label("传输到设备", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(activeDevice == nil || bleService.transferPhase == .transferring || bleService.transferPhase == .preparing)
        }
    }

    private var adjustmentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("手动调整")

            adjustmentSlider(title: "缩放", value: $adjustment.scale, range: 1...3)
            adjustmentSlider(title: "水平", value: $adjustment.offsetX, range: -160...160)
            adjustmentSlider(title: "垂直", value: $adjustment.offsetY, range: -160...160)

            Button {
                adjustment = .default
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
            profile: profile
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
