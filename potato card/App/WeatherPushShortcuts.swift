import AppIntents
import OSLog

struct WeatherPushIntent: AppIntent {
    static let title: LocalizedStringResource = "天气推送"
    static let description = IntentDescription("获取当前最新天气并推送到已绑定的墨水屏设备。")
    // iOS 16.5 仍使用 openAppWhenRun 控制后台执行；iOS 26 的 supportedModes 放在可用性扩展里。
    static let openAppWhenRun = false
    private let logger = Logger(subsystem: "com.xiaogousi.online.potato-card", category: "WeatherShortcut")

    func perform() async -> some IntentResult & ProvidesDialog {
        let message: String
        // 快捷指令要求纯后台运行，这里只返回结果文案，不主动拉起 App 界面。
        logger.info("天气推送快捷指令开始执行。")

        do {
            // 调试分支：后台快捷指令先等到真实块进度，再返回给系统，避免 status=4 后过早返回导致 SDK 停住。
            message = try await WeatherSkillPushCoordinator.shared.startLatestWeatherPushFromShortcut()
            logger.info("天气推送快捷指令执行成功：\(message, privacy: .public)")
        } catch {
            // 快捷指令直接抛错时，系统通常只显示“未知错误”，这里改成把真实原因返回给用户。
            message = Self.errorMessage(for: error)
            logger.error("天气推送快捷指令执行失败：\(message, privacy: .public)")
        }

        return .result(dialog: IntentDialog(stringLiteral: message))
    }

    private static func errorMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription, !description.isEmpty {
            return description
        }

        let fallback = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallback.isEmpty, fallback != "The operation couldn’t be completed." {
            return fallback
        }

        return "天气推送失败，请打开 App 检查天气配置、蓝牙权限和同步设备。"
    }
}

@available(iOS 26.0, *)
extension WeatherPushIntent {
    static var supportedModes: IntentModes { .background }
}

struct PotatoCardShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        return [
            AppShortcut(
                intent: WeatherPushIntent(),
                phrases: [
                    "用\(.applicationName)天气推送",
                    "在\(.applicationName)运行天气推送",
                    "\(.applicationName)推送天气"
                ],
                shortTitle: "天气推送",
                systemImageName: "cloud.sun.bolt"
            ),
            AppShortcut(
                intent: PushImageToCardIntent(),
                phrases: [
                    "用\(.applicationName)推送图片",
                    "把图片发到\(.applicationName)",
                    "\(.applicationName)推送图片到土豆片"
                ],
                shortTitle: "推送图片到土豆片",
                systemImageName: "photo.on.rectangle.angled"
            ),
            AppShortcut(
                intent: PushTextToCardIntent(),
                phrases: [
                    "用\(.applicationName)推送文字",
                    "把文字发到\(.applicationName)",
                    "\(.applicationName)推送文字到土豆片"
                ],
                shortTitle: "推送文字到土豆片",
                systemImageName: "text.alignleft"
            ),
            AppShortcut(
                intent: AIImageShortcutIntent(),
                phrases: [
                    "用\(.applicationName)AI 生图",
                    "在\(.applicationName)运行 AI 生图",
                    "\(.applicationName)生成图片"
                ],
                shortTitle: "AI 生图",
                systemImageName: "sparkles"
            )
        ]
    }
}
