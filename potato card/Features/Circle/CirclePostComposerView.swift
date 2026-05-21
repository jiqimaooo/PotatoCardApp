import PhotosUI
import SwiftUI
import UIKit

struct CirclePostComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var title = ""
    @State private var tagsText = ""
    @State private var isPublishing = false
    @State private var imageLoadFailed = false
    @State private var shouldUploadOriginal = false
    @FocusState private var focusedField: Field?

    let onPublish: (Data, String, [String]) -> Void
    // 外部传入的预制图片（图库长按 → 分享到圈子时已经按 400×600 渲染好），
    // 不为 nil 时直接使用，不再展示 PhotosPicker，也不会再次压缩。
    private let initialImageData: Data?
    // 允许用户换图。图库分享路径下传入 false，避免把外部裁好的图片改掉。
    private let allowsPhotoChange: Bool
    // 预制图是 400×600（2:3），使用原有 4:5 占位会让 scaledToFill 再裁
    // 一次，用户看到的就是「原始图」而不是手动调整后的预览。
    // 有预制图时切成 2/3，预览区 = 上传区 = 墨水屏区。
    private var photoPreviewAspectRatio: CGFloat { initialImageData != nil ? 2.0 / 3.0 : 0.82 }
    private let postUploadCompressionQuality: CGFloat = 0.82

    private enum Field: Hashable {
        case title
        case tags
    }

    init(
        initialImageData: Data? = nil,
        allowsPhotoChange: Bool = true,
        onPublish: @escaping (Data, String, [String]) -> Void
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
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = width / photoPreviewAspectRatio

            ZStack(alignment: .bottomLeading) {
                if allowsPhotoChange {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        photoPreviewContent(width: width, height: height)
                    }
                    .buttonStyle(.plain)
                    .disabled(isPublishing)
                    .accessibilityLabel(selectedItem == nil ? "选择照片" : "重新选择照片")
                } else {
                    // 图库长按 → 分享到圈子：图片已经裁好，只需重复预览，不提供重新选图。
                    photoPreviewContent(width: width, height: height)
                        .allowsHitTesting(false)
                }

                if allowsPhotoChange {
                    originalUploadButton
                }
            }
            .frame(width: width, height: height)
        }
        .aspectRatio(photoPreviewAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private func photoPreviewContent(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(photoFillColor)
                .frame(width: width, height: height)

            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        changePhotoBadge
                    }
            } else {
                emptyPhotoContent
                    .frame(width: width, height: height)
            }
        }
        .frame(width: width, height: height)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var emptyPhotoContent: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(redbookTint.opacity(0.11))
                    .frame(width: 74, height: 74)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(redbookTint)
            }

            VStack(spacing: 5) {
                Text(selectedItem == nil ? "选择一张照片" : "正在读取照片")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(primaryTextColor)

                Text(imageLoadFailed ? "读取失败，请重新选择" : "照片会用于圈子发布和土豆片传输")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(imageLoadFailed ? .red : secondaryTextColor)
                    .multilineTextAlignment(.center)
            }
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

    private var originalUploadButton: some View {
        Button {
            shouldUploadOriginal.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: shouldUploadOriginal ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .semibold))
                Text("原图")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.34), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isPublishing)
        .padding(12)
        .accessibilityLabel(shouldUploadOriginal ? "已选择上传原图" : "已关闭原图上传")
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

            Text("发布后，其他用户只能看到标题、标签和你的头像用户名；照片需要传输到土豆片查看。")
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

    private var selectedImage: UIImage? {
        guard let selectedImageData else { return nil }
        return UIImage(data: selectedImageData)
    }

    private var isPublishDisabled: Bool {
        // 原级设计是看 selectedItem，但现在可能是外部传入的 initialImageData，
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
            selectedImageData = try await selectedItem.loadTransferable(type: Data.self)
            imageLoadFailed = selectedImageData == nil
        } catch {
            selectedImageData = nil
            imageLoadFailed = true
        }
    }

    private func publish() {
        isPublishing = true
        focusedField = nil
        Task {
            let data: Data?
            if let selectedImageData {
                data = selectedImageData
            } else {
                data = try? await selectedItem?.loadTransferable(type: Data.self)
            }

            guard let data else {
                imageLoadFailed = true
                isPublishing = false
                return
            }
            let uploadData = preparedUploadData(from: data)
            let tags = tagsText
                .split(whereSeparator: { $0.isWhitespace || $0 == "," })
                .map(String.init)
            onPublish(uploadData, title.trimmingCharacters(in: .whitespacesAndNewlines), tags)
            dismiss()
        }
    }

    private func preparedUploadData(from data: Data) -> Data {
        // 外部传入的预制图已经是裁好的 400×600，不需要再压缩，避免二次损质。
        guard initialImageData == nil else { return data }
        guard !shouldUploadOriginal else { return data }
        guard let image = UIImage(data: data),
              let compressedData = image.jpegData(compressionQuality: postUploadCompressionQuality) else {
            return data
        }
        return compressedData
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.06, green: 0.06, blue: 0.07) : Color(red: 0.97, green: 0.97, blue: 0.96)
    }

    private var cardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : .white
    }

    private var photoFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.035)
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

struct CircleDriftBottleThrowComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var imageLoadFailed = false
    @State private var isSending = false
    @State private var isThrowing = false
    @State private var isPlaneLaunched = false

    let onThrow: (Data) -> Void
    private let initialImageData: Data?
    private let allowsPhotoChange: Bool

    // 预制图是 400×600（2:3）；有预制图时切成 2/3预览区 = 上传区。
    private var photoPreviewAspectRatio: CGFloat { initialImageData != nil ? 2.0 / 3.0 : 0.82 }
    private let uploadCompressionQuality: CGFloat = 0.82

    init(
        initialImageData: Data? = nil,
        allowsPhotoChange: Bool = true,
        onThrow: @escaping (Data) -> Void
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

            let uploadData = preparedUploadData(from: data)
            isPlaneLaunched = false
            withAnimation(.easeOut(duration: 0.12)) {
                isThrowing = true
            }
            try? await Task.sleep(nanoseconds: 80_000_000)
            withAnimation(.spring(response: 0.56, dampingFraction: 0.78)) {
                isPlaneLaunched = true
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            onThrow(uploadData)
            dismiss()
        }
    }

    private func preparedUploadData(from data: Data) -> Data {
        // 外部传入的预制图不再压缩，避免二次损质。
        guard initialImageData == nil else { return data }
        guard let image = UIImage(data: data),
              let compressedData = image.jpegData(compressionQuality: uploadCompressionQuality) else {
            return data
        }
        return compressedData
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
