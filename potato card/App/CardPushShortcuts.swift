//
//  CardPushShortcuts.swift
//  potato card
//
//  土豆片快捷指令的入口：
//  - 推送图片到土豆片：自动 cover 裁切，更新到墨水屏并存入图库。
//  - 推送文字到土豆片：从最大字号开始缩到刚好放下，居中并随机挑一种排版。
//

import AppIntents
import OSLog
import UIKit
import UniformTypeIdentifiers

struct PushImageToCardIntent: AppIntent {
    static let title: LocalizedStringResource = "推送图片到土豆片"
    static let description = IntentDescription(
        "把图片推送到已绑定的墨水屏，自动 cover 裁切，并保存到 App 图库。"
    )
    // 后台快捷指令模式，避免拉起 App 界面打断用户当前任务。
    static var supportedModes: IntentModes { .background }
    @available(*, deprecated, message: "保留给旧系统兼容，实际以 supportedModes 为准。")
    static let openAppWhenRun = false

    @Parameter(
        title: "图片",
        description: "要推送到土豆片的图片",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var image: IntentFile

    private static let logger = Logger(subsystem: "com.xiaogousi.online.potato-card", category: "CardPushShortcut")

    func perform() async -> some IntentResult & ProvidesDialog {
        Self.logger.info("收到推送图片快捷指令：name=\(image.filename, privacy: .public), size=\(image.data.count, privacy: .public) bytes")

        guard let uiImage = UIImage(data: image.data) else {
            return .result(dialog: IntentDialog(stringLiteral: CardPushError.invalidImage.localizedDescription))
        }

        do {
            let message = try await CardPushCoordinator.shared.pushImage(uiImage)
            return .result(dialog: IntentDialog(stringLiteral: message))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: CardPushIntentDialog.errorMessage(for: error)))
        }
    }
}

struct PushTextToCardIntent: AppIntent {
    static let title: LocalizedStringResource = "推送文字到土豆片"
    static let description = IntentDescription(
        "把文字渲染成图片推送到已绑定的墨水屏，自动适配字号，并保存到 App 图库。"
    )
    static var supportedModes: IntentModes { .background }
    @available(*, deprecated, message: "保留给旧系统兼容，实际以 supportedModes 为准。")
    static let openAppWhenRun = false

    @Parameter(
        title: "文字",
        description: "要显示在土豆片上的文字",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var text: String

    private static let logger = Logger(subsystem: "com.xiaogousi.online.potato-card", category: "CardPushShortcut")

    func perform() async -> some IntentResult & ProvidesDialog {
        Self.logger.info("收到推送文字快捷指令：length=\(text.count, privacy: .public)")

        do {
            let message = try await CardPushCoordinator.shared.pushText(text)
            return .result(dialog: IntentDialog(stringLiteral: message))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: CardPushIntentDialog.errorMessage(for: error)))
        }
    }
}

enum CardPushIntentDialog {
    // 把抛出的错误转成对用户友好的描述，避免快捷指令只显示「未知错误」。
    nonisolated static func errorMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription, !description.isEmpty {
            return description
        }
        let fallback = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallback.isEmpty, fallback != "The operation couldn’t be completed." {
            return fallback
        }
        return "推送失败，请打开 App 检查蓝牙权限和绑定设备。"
    }
}
