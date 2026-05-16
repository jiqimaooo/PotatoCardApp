import PhotosUI
import SwiftUI

struct CirclePostComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: PhotosPickerItem?
    @State private var title = ""
    @State private var tagsText = ""
    @State private var isPublishing = false

    let onPublish: (Data, String, [String]) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("照片") {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label(selectedItem == nil ? "选择照片" : "已选择照片", systemImage: "photo")
                    }
                    .disabled(isPublishing)
                }

                Section("信息") {
                    TextField("标题", text: $title)
                        .disabled(isPublishing)
                    TextField("标签，用空格或逗号分隔", text: $tagsText)
                        .disabled(isPublishing)
                }
            }
            .navigationTitle("发布作品")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .disabled(isPublishing)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(isPublishing ? "发布中" : "发布") {
                        publish()
                    }
                    .disabled(isPublishDisabled)
                }
            }
        }
    }

    private var isPublishDisabled: Bool {
        selectedItem == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPublishing
    }

    private func publish() {
        isPublishing = true
        Task {
            guard let data = try? await selectedItem?.loadTransferable(type: Data.self) else {
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
}
