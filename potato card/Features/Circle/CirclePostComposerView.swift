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
    @FocusState private var focusedField: Field?

    let onPublish: (Data, String, [String]) -> Void

    private enum Field: Hashable {
        case title
        case tags
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
        PhotosPicker(selection: $selectedItem, matching: .images) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(photoFillColor)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(0.82, contentMode: .fit)

                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .aspectRatio(0.82, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            changePhotoBadge
                        }
                } else {
                    emptyPhotoContent
                }
            }
            .overlay(alignment: .bottomLeading) {
                photoBottomLabel
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(cardStrokeColor, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isPublishing)
        .accessibilityLabel(selectedItem == nil ? "选择照片" : "重新选择照片")
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
        .aspectRatio(0.82, contentMode: .fit)
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

    private var photoBottomLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.display")
                .font(.system(size: 12, weight: .semibold))
            Text("圈子内不直接公开原图")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.34), in: Capsule())
        .padding(12)
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
        selectedItem == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPublishing
    }

    private func loadSelectedImageData() async {
        guard let selectedItem else {
            selectedImageData = nil
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
            let tags = tagsText
                .split(whereSeparator: { $0.isWhitespace || $0 == "," })
                .map(String.init)
            onPublish(data, title.trimmingCharacters(in: .whitespacesAndNewlines), tags)
            dismiss()
        }
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
