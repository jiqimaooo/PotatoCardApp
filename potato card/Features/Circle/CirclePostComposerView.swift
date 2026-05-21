import PhotosUI
import SwiftUI
import UIKit

struct CirclePostComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var bleService: BleTransferService
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var title = ""
    @State private var tagsText = ""
    @State private var isPublishing = false
    @State private var imageLoadFailed = false
    @State private var adjustment = EInkManualAdjustment.default
    @State private var selectedDitherAlgorithm: EInkDitherAlgorithm?
    @State private var isManualEditorExpanded = false
    @State private var isAlgorithmEditorExpanded = false
    @State private var publishErrorMessage: String?
    @State private var gestureScaleStart: CGFloat = 1
    @State private var gestureRotationStart: CGFloat = 0
    @State private var gestureOffsetStart: CGSize = .zero
    @FocusState private var focusedField: Field?

    let onPublish: (CirclePostUploadPayload, String, [String]) -> Void
    // 外部传入的预制图片（图库长按 → 分享到圈子时已经按 400×600 渲染好），
    // 不为 nil 时直接使用，不再展示 PhotosPicker，也不会再次压缩。
    private let initialImageData: Data?
    // 允许用户换图。图库分享路径下传入 false，避免把外部裁好的图片改掉。
    private let allowsPhotoChange: Bool
    private enum Field: Hashable {
        case title
        case tags
    }

    init(
        initialImageData: Data? = nil,
        allowsPhotoChange: Bool = true,
        onPublish: @escaping (CirclePostUploadPayload, String, [String]) -> Void
    ) {
        self.initialImageData = initialImageData
        self.allowsPhotoChange = allowsPhotoChange
        self.onPublish = onPublish
        _selectedImageData = State(initialValue: initialImageData)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        photoPickerCard
                        if let publishErrorMessage {
                            inlineErrorLabel(publishErrorMessage)
                        }
                        infoCard
                        helperCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(primaryTextColor)
                    .disabled(isPublishing)
                }

                ToolbarItem(placement: .principal) {
                    Text("发布作品")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        publish()
                    } label: {
                        HStack(spacing: 6) {
                            if isPublishing {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(.white)
                            }
                            Text(isPublishing ? "发布中" : "发布")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(isPublishDisabled ? Color.secondary.opacity(0.28) : redbookTint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isPublishDisabled)
                    .accessibilityLabel(isPublishing ? "发布中" : "发布作品")
                }
            }
        }
        .task(id: selectedItem) {
            await loadSelectedImageData()
        }
    }

    private var photoPickerCard: some View {
        VStack(spacing: 12) {
            if allowsPhotoChange && selectedImageData == nil {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    devicePreviewModel
                }
                .buttonStyle(.plain)
                .disabled(isPublishing)
                .accessibilityLabel("选择照片")
            } else {
                devicePreviewModel
            }

            HStack(spacing: 12) {
                manualEditButton
            }

            if isManualEditorExpanded {
                inlineEditorPanel
            }
        }
    }

    private var devicePreviewModel: some View {
        ZStack {
            ZStack {
                deviceScreenContent
                    .frame(width: 186, height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .offset(y: -19)

                Image("ink_tatoo2")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220)
                    .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 10)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 352)
        .overlay(alignment: .topTrailing) {
            if selectedImage != nil && allowsPhotoChange {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    changePhotoBadge
                }
                .buttonStyle(.plain)
                .disabled(isPublishing)
                .accessibilityLabel("重新选择照片")
                .offset(x: 24, y: 8)
            }
        }
        .contentShape(Rectangle())
    }

    private var deviceScreenContent: some View {
        Group {
            if let selectedImage {
                GeometryReader { proxy in
                    let baseScale = max(
                        proxy.size.width / selectedImage.size.width,
                        proxy.size.height / selectedImage.size.height
                    )
                    let offsetScale = min(
                        proxy.size.width / PotatoDevicePayloadCodec.targetSize.width,
                        proxy.size.height / PotatoDevicePayloadCodec.targetSize.height
                    )

                    Image(uiImage: selectedImage)
                        .resizable()
                        .interpolation(.medium)
                        .frame(
                            width: selectedImage.size.width * baseScale,
                            height: selectedImage.size.height * baseScale
                        )
                        .scaleEffect(adjustment.scale)
                        .rotationEffect(.radians(Double(adjustment.rotation)))
                        .offset(x: adjustment.offsetX * offsetScale, y: adjustment.offsetY * offsetScale)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .background(Color.white)
                .gesture(isPublishing ? nil : screenEditGesture)
            } else {
                emptyDeviceScreen
            }
        }
        .clipped()
    }

    private var emptyDeviceScreen: some View {
        VStack(spacing: 10) {
            Image(systemName: imageLoadFailed ? "exclamationmark.triangle.fill" : "photo.badge.plus")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(imageLoadFailed ? .red : redbookTint)

            Text(imageLoadFailed ? "读取失败" : "选择照片")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(primaryTextColor)

            Text("点此添加")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    private var manualEditButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                isManualEditorExpanded.toggle()
            }
        } label: {
            Label(isManualEditorExpanded ? "收起编辑" : "手动编辑", systemImage: "slider.horizontal.3")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selectedImageData == nil ? secondaryTextColor : primaryTextColor)
                .padding(.horizontal, 16)
                .frame(height: 42)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(selectedImageData == nil || isPublishing)
    }

    private var changePhotoBadge: some View {
        Label("更换", systemImage: "arrow.triangle.2.circlepath")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(primaryTextColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
    }

    private var inlineEditorPanel: some View {
        VStack(spacing: 0) {
            editorHeader

            Divider()
                .overlay(dividerColor)
                .padding(.leading, 14)

            VStack(spacing: 14) {
                sliderRow(title: "缩放", value: $adjustment.scale, range: 0.25...3, format: scalePercent)
                sliderRow(title: "旋转", value: $adjustment.rotation, range: -.pi...(.pi), format: rotationDegrees)
                sliderRow(title: "水平", value: $adjustment.offsetX, range: -160...160, format: offsetText)
                sliderRow(title: "垂直", value: $adjustment.offsetY, range: -160...160, format: offsetText)
                algorithmEditor
            }
            .padding(14)
        }
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        }
    }

    private var editorHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("手动编辑")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                Text(adjustmentSummary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
            }

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    resetAdjustment()
                }
            } label: {
                Label("重置", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .disabled(adjustment == .default && selectedDitherAlgorithm == nil)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
    }

    private var algorithmEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                    isAlgorithmEditorExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("图像算法")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(primaryTextColor)
                        Text(selectedAlgorithmTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                        .rotationEffect(.degrees(isAlgorithmEditorExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isAlgorithmEditorExpanded {
                VStack(spacing: 0) {
                    algorithmOption(title: "默认", subtitle: "跟随我的页面全局算法：\(bleService.ditherAlgorithm.title)", algorithm: nil)
                    ForEach(EInkDitherAlgorithm.allCases) { algorithm in
                        Divider().overlay(dividerColor)
                        algorithmOption(title: algorithm.title, subtitle: algorithm.subtitle, algorithm: algorithm)
                    }
                }
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func algorithmOption(title: String, subtitle: String, algorithm: EInkDitherAlgorithm?) -> some View {
        Button {
            selectedDitherAlgorithm = algorithm
            withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                isAlgorithmEditorExpanded = false
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                }

                Spacer()

                if selectedDitherAlgorithm == algorithm {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(redbookTint)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(secondaryTextColor)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(primaryTextColor)

            Slider(value: value, in: range)
                .tint(redbookTint)
                .disabled(isPublishing)
        }
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            composerRow(
                label: "标题",
                systemImage: "text.alignleft",
                isFocused: focusedField == .title
            ) {
                TextField("给作品起个标题", text: $title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(primaryTextColor)
                    .focused($focusedField, equals: .title)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .disabled(isPublishing)
                    .onSubmit {
                        focusedField = .tags
                    }
            }

            Divider()
                .overlay(dividerColor)
                .padding(.leading, 52)

            composerRow(
                label: "标签",
                systemImage: "number",
                isFocused: focusedField == .tags
            ) {
                TextField("用空格或逗号分隔", text: $tagsText)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(primaryTextColor)
                    .focused($focusedField, equals: .tags)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .disabled(isPublishing)
            }
        }
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        }
    }

    private func composerRow<Content: View>(
        label: String,
        systemImage: String,
        isFocused: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isFocused ? redbookTint : secondaryTextColor)
                .frame(width: 28, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)

                content()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 76)
        .contentShape(Rectangle())
    }

    private var helperCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "paperplane")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(redbookTint)
                .frame(width: 24, height: 24)

            Text("你对图片所进行的尺寸调整、算法处理等内容，在发布后会随作品一同保存。")
                .font(.system(size: 13, weight: .medium))
                .lineSpacing(2)
                .foregroundStyle(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        }
    }

    private func inlineErrorLabel(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.red)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(colorScheme == .dark ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var selectedImage: UIImage? {
        guard let selectedImageData else { return nil }
        return UIImage(data: selectedImageData)
    }

    private var isPublishDisabled: Bool {
        // 原先设计是看 selectedItem，但现在可能是外部传入的 initialImageData，
        // 统一看 selectedImageData 是否存在。
        selectedImageData == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPublishing
    }

    private func loadSelectedImageData() async {
        guard let selectedItem else {
            // 外部传入的预制图不走这条重置路径，避免刚进页面就被清掉。
            if initialImageData == nil {
                selectedImageData = nil
            }
            imageLoadFailed = false
            return
        }
        imageLoadFailed = false
        do {
            let data = try await selectedItem.loadTransferable(type: Data.self)
            selectedImageData = data
            publishErrorMessage = nil
            resetAdjustment()
            imageLoadFailed = data == nil
        } catch {
            selectedImageData = nil
            publishErrorMessage = "照片读取失败，请重新选择"
            imageLoadFailed = true
        }
    }

    private func publish() {
        isPublishing = true
        publishErrorMessage = nil
        focusedField = nil

        Task {
            guard let selectedImageData else {
                imageLoadFailed = true
                publishErrorMessage = "请先选择照片"
                isPublishing = false
                return
            }
            guard let image = UIImage(data: selectedImageData) else {
                imageLoadFailed = true
                publishErrorMessage = "照片无法读取，请重新选择"
                isPublishing = false
                return
            }

            do {
                let originalData = try CircleUploadImageCompressor.compressedDisplayJPEGData(from: image)
                let result = try PotatoDevicePayloadCodec.build(
                    sourceImage: image,
                    adjustment: adjustment,
                    ditherAlgorithm: effectiveDitherAlgorithm
                )
                let payload = CirclePostUploadPayload(
                    originalImageData: originalData,
                    devicePayloadData: result.data,
                    payloadMeta: result.meta
                )

                onPublish(payload, title.trimmingCharacters(in: .whitespacesAndNewlines), normalizedTags())
                dismiss()
            } catch {
                publishErrorMessage = error.localizedDescription
                isPublishing = false
            }
        }
    }

    private func resetAdjustment() {
        adjustment = .default
        selectedDitherAlgorithm = nil
        gestureScaleStart = adjustment.scale
        gestureRotationStart = adjustment.rotation
        gestureOffsetStart = CGSize(width: adjustment.offsetX, height: adjustment.offsetY)
    }

    private var screenEditGesture: some Gesture {
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

        let drag = DragGesture()
            .onChanged { value in
                adjustment.offsetX = clampOffset(gestureOffsetStart.width + value.translation.width)
                adjustment.offsetY = clampOffset(gestureOffsetStart.height + value.translation.height)
            }
            .onEnded { _ in
                gestureOffsetStart = CGSize(width: adjustment.offsetX, height: adjustment.offsetY)
            }

        return SimultaneousGesture(SimultaneousGesture(magnify, rotate), drag)
    }

    private func clampScale(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.25), 3)
    }

    private func clampRotation(_ value: CGFloat) -> CGFloat {
        min(max(value, -.pi), .pi)
    }

    private func clampOffset(_ value: CGFloat) -> CGFloat {
        min(max(value, -160), 160)
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

    private func normalizedTags() -> [String] {
        tagsText
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.06, green: 0.06, blue: 0.07) : Color(red: 0.97, green: 0.97, blue: 0.96)
    }

    private var cardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : .white
    }

    private var cardStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.055)
    }

    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.88)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.50)
    }

    private var redbookTint: Color {
        Color(red: 0.86, green: 0.16, blue: 0.22)
    }
}

private struct LegacyCircleDriftBottleThrowComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var imageLoadFailed = false
    @State private var isSending = false
    @State private var isThrowing = false
    @State private var isPlaneLaunched = false
    @State private var isImageEditorPresented = false
    @State private var editorSourceImage: UIImage?
    @State private var editorOriginalImageData: Data?

    let onThrow: (CirclePostUploadPayload) -> Void
    private let initialImageData: Data?
    private let allowsPhotoChange: Bool

    // 预制图是 400×600（2:3）；有预制图时切成 2/3预览区 = 上传区。
    private var photoPreviewAspectRatio: CGFloat { initialImageData != nil ? 2.0 / 3.0 : 0.82 }

    init(
        initialImageData: Data? = nil,
        allowsPhotoChange: Bool = true,
        onThrow: @escaping (CirclePostUploadPayload) -> Void
    ) {
        self.initialImageData = initialImageData
        self.allowsPhotoChange = allowsPhotoChange
        self.onThrow = onThrow
        _selectedImageData = State(initialValue: initialImageData)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()

                VStack(spacing: 18) {
                    Spacer(minLength: 12)

                    photoPickerCard
                        .padding(.horizontal, 18)

                    Spacer(minLength: 18)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(primaryTextColor)
                    .disabled(isSending)
                }

                ToolbarItem(placement: .principal) {
                    Text("扔一个")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: send) {
                        Text("发送")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isSendDisabled ? secondaryTextColor : driftTint)
                    }
                    .disabled(isSendDisabled)
                }
            }
        }
        .task(id: selectedItem) {
            await loadSelectedImageData()
        }
        .sheet(isPresented: $isImageEditorPresented) {
            if let editorSourceImage, let editorOriginalImageData {
                CirclePostImageEditorView(
                    sourceImage: editorSourceImage,
                    originalImageData: editorOriginalImageData,
                    footerText: "扔出前将同时生成土豆片专用显示数据",
                    confirmButtonTitle: "确认扔出"
                ) { uploadPayload in
                    animateThrowAndFinish(uploadPayload)
                }
            } else {
                ProgressView("正在读取照片…")
                    .presentationDetents([.height(220)])
            }
        }
    }

    private var photoPickerCard: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = width / photoPreviewAspectRatio

            ZStack {
                if allowsPhotoChange {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        photoPreviewContent(width: width, height: height)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)
                } else {
                    photoPreviewContent(width: width, height: height)
                        .allowsHitTesting(false)
                }

                if isThrowing {
                    thrownPlane
                        .transition(.scale(scale: 0.76).combined(with: .opacity))
                }
            }
            .frame(width: width, height: height)
        }
        .aspectRatio(photoPreviewAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private func photoPreviewContent(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(photoFillColor)
                .frame(width: width, height: height)

            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .scaleEffect(isThrowing ? 0.22 : 1)
                    .rotationEffect(.degrees(isThrowing ? 22 : 0))
                    .offset(x: isThrowing ? width * 0.36 : 0, y: isThrowing ? -height * 0.48 : 0)
                    .opacity(isThrowing ? 0 : 1)
                    .animation(.spring(response: 0.58, dampingFraction: 0.82), value: isThrowing)
                    .overlay(alignment: .topTrailing) {
                        if !isThrowing {
                            changePhotoBadge
                        }
                    }
            } else {
                emptyPhotoContent
                    .frame(width: width, height: height)
            }
        }
        .frame(width: width, height: height)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var emptyPhotoContent: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(driftTint.opacity(0.11))
                    .frame(width: 74, height: 74)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(driftTint)
            }

            Text(imageLoadFailed ? "读取失败，请重新选择" : "选择照片")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(imageLoadFailed ? .red : primaryTextColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var changePhotoBadge: some View {
        Label("更换", systemImage: "arrow.triangle.2.circlepath")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(primaryTextColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .padding(10)
    }

    private var thrownPlane: some View {
        Image(systemName: "paperplane.fill")
            .font(.system(size: 36, weight: .bold))
            .foregroundStyle(driftTint)
            .shadow(color: driftTint.opacity(0.28), radius: 18, x: 0, y: 8)
            .offset(x: isPlaneLaunched ? 112 : -18, y: isPlaneLaunched ? -164 : 40)
            .rotationEffect(.degrees(isPlaneLaunched ? 16 : -18))
            .scaleEffect(isPlaneLaunched ? 0.76 : 1)
            .opacity(isPlaneLaunched ? 0 : 1)
            .animation(.spring(response: 0.56, dampingFraction: 0.78), value: isPlaneLaunched)
    }

    private var selectedImage: UIImage? {
        guard let selectedImageData else { return nil }
        return UIImage(data: selectedImageData)
    }

    private var isSendDisabled: Bool {
        selectedImageData == nil || isSending
    }

    private func loadSelectedImageData() async {
        guard let selectedItem else {
            if initialImageData == nil {
                selectedImageData = nil
            }
            imageLoadFailed = false
            return
        }
        imageLoadFailed = false
        do {
            selectedImageData = try await selectedItem.loadTransferable(type: Data.self)
            imageLoadFailed = selectedImageData == nil
        } catch {
            selectedImageData = nil
            imageLoadFailed = true
        }
    }

    private func send() {
        guard !isSendDisabled else { return }
        isSending = true

        Task {
            let data: Data?
            if let selectedImageData {
                data = selectedImageData
            } else {
                data = try? await selectedItem?.loadTransferable(type: Data.self)
            }

            guard let data else {
                imageLoadFailed = true
                isSending = false
                return
            }

            guard let image = UIImage(data: data) else {
                imageLoadFailed = true
                isSending = false
                return
            }
            editorSourceImage = image
            editorOriginalImageData = data
            isSending = false
            isImageEditorPresented = true
        }
    }

    private func animateThrowAndFinish(_ uploadPayload: CirclePostUploadPayload) {
        isPlaneLaunched = false
        withAnimation(.easeOut(duration: 0.12)) {
            isThrowing = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            await MainActor.run {
                withAnimation(.spring(response: 0.56, dampingFraction: 0.78)) {
                    isPlaneLaunched = true
                }
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            await MainActor.run {
                onThrow(uploadPayload)
                dismiss()
            }
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.06, green: 0.06, blue: 0.07) : Color(red: 0.97, green: 0.97, blue: 0.96)
    }

    private var photoFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.035)
    }

    private var cardStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.055)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.88)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.46) : Color.black.opacity(0.38)
    }

    private var driftTint: Color {
        Color(red: 0.08, green: 0.48, blue: 0.86)
    }
}

struct CircleDriftBottleThrowComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var bleService: BleTransferService
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var imageLoadFailed = false
    @State private var isSending = false
    @State private var adjustment = EInkManualAdjustment.default
    @State private var selectedDitherAlgorithm: EInkDitherAlgorithm?
    @State private var isManualEditorExpanded = false
    @State private var isAlgorithmEditorExpanded = false
    @State private var sendErrorMessage: String?
    @State private var gestureScaleStart: CGFloat = 1
    @State private var gestureRotationStart: CGFloat = 0
    @State private var gestureOffsetStart: CGSize = .zero

    let onThrow: (CirclePostUploadPayload) -> Void
    private let initialImageData: Data?
    private let allowsPhotoChange: Bool

    init(
        initialImageData: Data? = nil,
        allowsPhotoChange: Bool = true,
        onThrow: @escaping (CirclePostUploadPayload) -> Void
    ) {
        self.initialImageData = initialImageData
        self.allowsPhotoChange = allowsPhotoChange
        self.onThrow = onThrow
        _selectedImageData = State(initialValue: initialImageData)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        photoPickerCard
                        if let sendErrorMessage {
                            inlineErrorLabel(sendErrorMessage)
                        }
                        helperCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(primaryTextColor)
                    .disabled(isSending)
                }

                ToolbarItem(placement: .principal) {
                    Text("扔一个")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: send) {
                        HStack(spacing: 6) {
                            if isSending {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(.white)
                            }
                            Text(isSending ? "发送中" : "发送")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(isSendDisabled ? Color.secondary.opacity(0.28) : driftTint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSendDisabled)
                }
            }
        }
        .task(id: selectedItem) {
            await loadSelectedImageData()
        }
    }

    private var photoPickerCard: some View {
        VStack(spacing: 12) {
            if allowsPhotoChange && selectedImageData == nil {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    devicePreviewModel
                }
                .buttonStyle(.plain)
                .disabled(isSending)
                .accessibilityLabel("选择照片")
            } else {
                devicePreviewModel
            }

            HStack(spacing: 12) {
                manualEditButton
            }

            if isManualEditorExpanded {
                inlineEditorPanel
            }
        }
    }

    private var devicePreviewModel: some View {
        ZStack {
            ZStack {
                deviceScreenContent
                    .frame(width: 186, height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .offset(y: -19)

                Image("ink_tatoo2")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220)
                    .shadow(color: Color.black.opacity(0.14), radius: 16, x: 0, y: 10)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 352)
        .overlay(alignment: .topTrailing) {
            if selectedImage != nil && allowsPhotoChange {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    changePhotoBadge
                }
                .buttonStyle(.plain)
                .disabled(isSending)
                .accessibilityLabel("重新选择照片")
                .offset(x: 24, y: 8)
            }
        }
        .contentShape(Rectangle())
    }

    private var deviceScreenContent: some View {
        Group {
            if let selectedImage {
                GeometryReader { proxy in
                    let baseScale = max(
                        proxy.size.width / selectedImage.size.width,
                        proxy.size.height / selectedImage.size.height
                    )
                    let offsetScale = min(
                        proxy.size.width / PotatoDevicePayloadCodec.targetSize.width,
                        proxy.size.height / PotatoDevicePayloadCodec.targetSize.height
                    )

                    Image(uiImage: selectedImage)
                        .resizable()
                        .interpolation(.medium)
                        .frame(
                            width: selectedImage.size.width * baseScale,
                            height: selectedImage.size.height * baseScale
                        )
                        .scaleEffect(adjustment.scale)
                        .rotationEffect(.radians(Double(adjustment.rotation)))
                        .offset(x: adjustment.offsetX * offsetScale, y: adjustment.offsetY * offsetScale)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .background(Color.white)
                .gesture(isSending ? nil : screenEditGesture)
            } else {
                emptyDeviceScreen
            }
        }
        .clipped()
    }

    private var emptyDeviceScreen: some View {
        VStack(spacing: 10) {
            Image(systemName: imageLoadFailed ? "exclamationmark.triangle.fill" : "photo.badge.plus")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(imageLoadFailed ? .red : driftTint)

            Text(imageLoadFailed ? "读取失败" : "选择照片")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(primaryTextColor)

            Text("点此添加")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    private var manualEditButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                isManualEditorExpanded.toggle()
            }
        } label: {
            Label(isManualEditorExpanded ? "收起编辑" : "手动编辑", systemImage: "slider.horizontal.3")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selectedImageData == nil ? secondaryTextColor : primaryTextColor)
                .padding(.horizontal, 16)
                .frame(height: 42)
                .background(Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(selectedImageData == nil || isSending)
    }

    private var changePhotoBadge: some View {
        Label("更换", systemImage: "arrow.triangle.2.circlepath")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(primaryTextColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
    }

    private var inlineEditorPanel: some View {
        VStack(spacing: 0) {
            editorHeader

            Divider()
                .overlay(dividerColor)
                .padding(.leading, 14)

            VStack(spacing: 14) {
                sliderRow(title: "缩放", value: $adjustment.scale, range: 0.25...3, format: scalePercent)
                sliderRow(title: "旋转", value: $adjustment.rotation, range: -.pi...(.pi), format: rotationDegrees)
                sliderRow(title: "水平", value: $adjustment.offsetX, range: -160...160, format: offsetText)
                sliderRow(title: "垂直", value: $adjustment.offsetY, range: -160...160, format: offsetText)
                algorithmEditor
            }
            .padding(14)
        }
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        }
    }

    private var editorHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("手动编辑")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                Text(adjustmentSummary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
            }

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    resetAdjustment()
                }
            } label: {
                Label("重置", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .disabled(adjustment == .default && selectedDitherAlgorithm == nil)
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
    }

    private var algorithmEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
                    isAlgorithmEditorExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("图像算法")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(primaryTextColor)
                        Text(selectedAlgorithmTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                        .rotationEffect(.degrees(isAlgorithmEditorExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isAlgorithmEditorExpanded {
                VStack(spacing: 0) {
                    algorithmOption(title: "默认", subtitle: "跟随我的页面全局算法：\(bleService.ditherAlgorithm.title)", algorithm: nil)
                    ForEach(EInkDitherAlgorithm.allCases) { algorithm in
                        Divider().overlay(dividerColor)
                        algorithmOption(title: algorithm.title, subtitle: algorithm.subtitle, algorithm: algorithm)
                    }
                }
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func algorithmOption(title: String, subtitle: String, algorithm: EInkDitherAlgorithm?) -> some View {
        Button {
            selectedDitherAlgorithm = algorithm
            withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                isAlgorithmEditorExpanded = false
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                }

                Spacer()

                if selectedDitherAlgorithm == algorithm {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(driftTint)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(secondaryTextColor)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(primaryTextColor)

            Slider(value: value, in: range)
                .tint(driftTint)
                .disabled(isSending)
        }
    }

    private var helperCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "paperplane")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(driftTint)
                .frame(width: 24, height: 24)

            Text("漂流瓶只需要选择图片并确认显示效果；扔出后会保存展示图和土豆片专用显示数据。")
                .font(.system(size: 13, weight: .medium))
                .lineSpacing(2)
                .foregroundStyle(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        }
    }

    private func inlineErrorLabel(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.red)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(colorScheme == .dark ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var selectedImage: UIImage? {
        guard let selectedImageData else { return nil }
        return UIImage(data: selectedImageData)
    }

    private var isSendDisabled: Bool {
        selectedImageData == nil || isSending
    }

    private func loadSelectedImageData() async {
        guard let selectedItem else {
            if initialImageData == nil {
                selectedImageData = nil
            }
            imageLoadFailed = false
            return
        }
        imageLoadFailed = false
        do {
            let data = try await selectedItem.loadTransferable(type: Data.self)
            selectedImageData = data
            sendErrorMessage = nil
            resetAdjustment()
            imageLoadFailed = data == nil
        } catch {
            selectedImageData = nil
            sendErrorMessage = "照片读取失败，请重新选择"
            imageLoadFailed = true
        }
    }

    private func send() {
        guard !isSendDisabled else { return }
        isSending = true
        sendErrorMessage = nil

        Task {
            guard let selectedImageData else {
                imageLoadFailed = true
                sendErrorMessage = "请先选择照片"
                isSending = false
                return
            }
            guard let image = UIImage(data: selectedImageData) else {
                imageLoadFailed = true
                sendErrorMessage = "照片无法读取，请重新选择"
                isSending = false
                return
            }

            do {
                let originalData = try CircleUploadImageCompressor.compressedDisplayJPEGData(from: image)
                let result = try PotatoDevicePayloadCodec.build(
                    sourceImage: image,
                    adjustment: adjustment,
                    ditherAlgorithm: effectiveDitherAlgorithm
                )
                let uploadPayload = CirclePostUploadPayload(
                    originalImageData: originalData,
                    devicePayloadData: result.data,
                    payloadMeta: result.meta
                )

                onThrow(uploadPayload)
                dismiss()
            } catch {
                sendErrorMessage = error.localizedDescription
                isSending = false
            }
        }
    }

    private func resetAdjustment() {
        adjustment = .default
        selectedDitherAlgorithm = nil
        gestureScaleStart = adjustment.scale
        gestureRotationStart = adjustment.rotation
        gestureOffsetStart = CGSize(width: adjustment.offsetX, height: adjustment.offsetY)
    }

    private var screenEditGesture: some Gesture {
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

        let drag = DragGesture()
            .onChanged { value in
                adjustment.offsetX = clampOffset(gestureOffsetStart.width + value.translation.width)
                adjustment.offsetY = clampOffset(gestureOffsetStart.height + value.translation.height)
            }
            .onEnded { _ in
                gestureOffsetStart = CGSize(width: adjustment.offsetX, height: adjustment.offsetY)
            }

        return SimultaneousGesture(SimultaneousGesture(magnify, rotate), drag)
    }

    private func clampScale(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.25), 3)
    }

    private func clampRotation(_ value: CGFloat) -> CGFloat {
        min(max(value, -.pi), .pi)
    }

    private func clampOffset(_ value: CGFloat) -> CGFloat {
        min(max(value, -160), 160)
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

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.06, green: 0.06, blue: 0.07) : Color(red: 0.97, green: 0.97, blue: 0.96)
    }

    private var cardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : .white
    }

    private var cardStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.055)
    }

    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.88)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.50)
    }

    private var driftTint: Color {
        Color(red: 0.08, green: 0.48, blue: 0.86)
    }
}
