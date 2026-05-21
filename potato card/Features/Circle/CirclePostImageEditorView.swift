import SwiftUI
import UIKit

struct CirclePostImageEditorView: View {
    let sourceImage: UIImage
    let originalImageData: Data
    let footerText: String
    let confirmButtonTitle: String
    let onConfirm: (CirclePostUploadPayload) -> Void

    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.dismiss) private var dismiss
    @State private var adjustment = EInkManualAdjustment.default
    @State private var selectedDitherAlgorithm: EInkDitherAlgorithm?
    @State private var isAdjustmentExpanded = true
    @State private var isAlgorithmExpanded = false
    @State private var isGenerating = false
    @State private var progressTitle = "确认并发布"
    @State private var errorMessage: String?

    init(
        sourceImage: UIImage,
        originalImageData: Data,
        footerText: String = "发布后将同时生成土豆片专用显示数据",
        confirmButtonTitle: String = "确认发布",
        onConfirm: @escaping (CirclePostUploadPayload) -> Void
    ) {
        self.sourceImage = sourceImage
        self.originalImageData = originalImageData
        self.footerText = footerText
        self.confirmButtonTitle = confirmButtonTitle
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    InteractiveDevicePreview(
                        sourceImage: sourceImage,
                        adjustment: $adjustment,
                        renderTargetSize: PotatoDevicePayloadCodec.targetSize,
                        isInteractive: !isGenerating
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text(footerText)
                }

                adjustmentSection
                algorithmSection
            }
            .formStyle(.grouped)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomActionBar
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("返回") {
                        dismiss()
                    }
                    .disabled(isGenerating)
                }

                ToolbarItem(placement: .principal) {
                    Text("预览编辑")
                        .font(.headline)
                }
            }
        }
    }

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
                        Text(adjustmentSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if adjustment != .default {
                        Button("重置", systemImage: "arrow.counterclockwise") {
                            withAnimation(.easeOut(duration: 0.2)) {
                                adjustment = .default
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .disabled(isGenerating)
                    }
                }
            }
        }
    }

    private var algorithmSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isAlgorithmExpanded) {
                defaultAlgorithmRow
                ForEach(EInkDitherAlgorithm.allCases) { algorithm in
                    algorithmRow(algorithm)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("图像算法")
                        .font(.headline)
                    Text(selectedAlgorithmTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var defaultAlgorithmRow: some View {
        Button {
            selectedDitherAlgorithm = nil
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("默认")
                    Text("跟随我的页面全局算法：\(bleService.ditherAlgorithm.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedDitherAlgorithm == nil {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
    }

    private func algorithmRow(_ algorithm: EInkDitherAlgorithm) -> some View {
        Button {
            selectedDitherAlgorithm = algorithm
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(algorithm.title)
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
        .disabled(isGenerating)
    }

    private var bottomActionBar: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                generatePayloadAndPublish()
            } label: {
                TransferProgressButtonLabel(
                    title: confirmButtonTitle,
                    progressTitle: progressTitle,
                    progress: isGenerating ? 0.66 : 0,
                    isInProgress: isGenerating,
                    height: 50,
                    cornerRadius: 25,
                    accentColor: Color(red: 0.86, green: 0.16, blue: 0.22)
                )
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private func generatePayloadAndPublish() {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        progressTitle = "正在处理图片…"

        Task {
            do {
                let originalData = try preparedOriginalData()
                progressTitle = "正在生成土豆片数据…"
                let result = try PotatoDevicePayloadCodec.build(
                    sourceImage: sourceImage,
                    adjustment: adjustment,
                    ditherAlgorithm: effectiveDitherAlgorithm
                )
                progressTitle = "正在上传…"
                onConfirm(CirclePostUploadPayload(
                    originalImageData: originalData,
                    devicePayloadData: result.data,
                    payloadMeta: result.meta
                ))
                dismiss()
            } catch {
            errorMessage = error.localizedDescription
            isGenerating = false
            progressTitle = confirmButtonTitle
        }
    }
    }

    private func preparedOriginalData() throws -> Data {
        try CircleUploadImageCompressor.compressedDisplayJPEGData(from: sourceImage)
    }

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
                .disabled(isGenerating)
        }
    }

    private var effectiveDitherAlgorithm: EInkDitherAlgorithm {
        selectedDitherAlgorithm ?? bleService.ditherAlgorithm
    }

    private var selectedAlgorithmTitle: String {
        if let selectedDitherAlgorithm {
            return selectedDitherAlgorithm.title
        }
        return "默认 · \(bleService.ditherAlgorithm.title)"
    }

    private var adjustmentSummary: String {
        if adjustment == .default {
            return "未调整"
        }
        return [
            scalePercent(adjustment.scale),
            rotationDegrees(adjustment.rotation),
            offsetText(adjustment.offsetX) + " / " + offsetText(adjustment.offsetY),
        ].joined(separator: " · ")
    }

    private func scalePercent(_ value: CGFloat) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func rotationDegrees(_ value: CGFloat) -> String {
        String(format: "%.0f°", value * 180 / .pi)
    }

    private func offsetText(_ value: CGFloat) -> String {
        "\(Int(value.rounded()))"
    }
}
