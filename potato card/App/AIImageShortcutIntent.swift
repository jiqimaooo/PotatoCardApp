import AppIntents
import Foundation

struct AIImageShortcutIntent: AppIntent {
    static let title: LocalizedStringResource = "AI 生图"
    static let description = IntentDescription("根据输入 Prompt 调用已配置的模型服务生成图片。")
    static let openAppWhenRun = false

    @Parameter(title: "Prompt", description: "描述你想生成的图片")
    var prompt: String

    @Parameter(title: "模型服务", description: "不选择时使用 App 内 AI 生图配置")
    var modelProvider: AIImageModelProvider?

    @Parameter(title: "图片尺寸", description: "留空默认为 400*600")
    var size: String?

    @Parameter(title: "是否保存至 App 图库", default: true)
    var saveToAppGallery: Bool

    @Parameter(title: "是否保存至系统相册", default: true)
    var saveToSystemPhotos: Bool

    func perform() async -> some IntentResult & ProvidesDialog {
        let parsedSize: AIImageSize?
        if let size, !size.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let value = await MainActor.run {
                AIImageSize.parse(size)
            }
            guard let value else {
                ShortcutDebugLog.log("AIImageShortcutIntent", "perform failed invalid size=\(size)")
                return .result(dialog: IntentDialog(stringLiteral: "图片尺寸格式无效，请使用 400x600 这样的格式。"))
            }
            parsedSize = value
        } else {
            parsedSize = nil
        }

        do {
            let result = try await AIImageGenerationService().generate(
                prompt: prompt,
                provider: modelProvider,
                size: parsedSize,
                saveToAppGallery: saveToAppGallery,
                saveToSystemPhotos: saveToSystemPhotos
            )
            ShortcutDebugLog.log("AIImageShortcutIntent", "perform success bytes=\(result.pngData.count) saveToAppGallery=\(saveToAppGallery) saveToSystemPhotos=\(saveToSystemPhotos)")
            return .result(dialog: IntentDialog(stringLiteral: "AI 生图完成"))
        } catch {
            let parsed = AIImageErrorParser.parse(error, provider: modelProvider)
            ShortcutDebugLog.log("AIImageShortcutIntent", "perform failed message=\(parsed.message) raw=\(parsed.rawLog)")
            return .result(dialog: IntentDialog(stringLiteral: parsed.message))
        }
    }
}

@available(iOS 26.0, *)
extension AIImageShortcutIntent {
    static var supportedModes: IntentModes { .background }
}
