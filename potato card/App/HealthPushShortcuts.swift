//
//  HealthPushShortcuts.swift
//  potato card
//
//  健康看板的快捷指令入口：
//  - 单一参数 mode 决定推送的是“睡眠 / 健身 / 一日总结”，避免注册 3 个 Intent。
//  - 也额外注册 3 个无参数包装，方便用户在“快捷指令”里直接挑模式。
//

import AppIntents
import OSLog

// AppEnum 必须显式声明 caseDisplayRepresentations，否则快捷指令选择面板里只展示 raw。
enum HealthDashboardModeIntent: String, AppEnum, CaseIterable {
    case sleep
    case fitness
    case daily

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "健康看板模式"

    static let caseDisplayRepresentations: [HealthDashboardModeIntent: DisplayRepresentation] = [
        .sleep: DisplayRepresentation(title: "睡眠看板"),
        .fitness: DisplayRepresentation(title: "健身看板"),
        .daily: DisplayRepresentation(title: "一日总结")
    ]

    var domainMode: HealthDashboardMode {
        switch self {
        case .sleep: return .sleep
        case .fitness: return .fitness
        case .daily: return .daily
        }
    }
}

struct HealthPushIntent: AppIntent {
    static let title: LocalizedStringResource = "健康看板推送"
    static let description = IntentDescription("把指定模式的健康看板推送到已绑定的墨水屏设备。")
    static let openAppWhenRun = false

    @Parameter(title: "看板模式", description: "选择要推送的健康看板模式")
    var mode: HealthDashboardModeIntent

    private static let logger = Logger(subsystem: "com.xiaogousi.online.potato-card", category: "HealthShortcut")

    init() {
        self.mode = .daily
    }

    init(mode: HealthDashboardModeIntent) {
        self.mode = mode
    }

    func perform() async -> some IntentResult & ProvidesDialog {
        let message: String
        Self.logger.info("健康推送快捷指令开始执行 mode=\(self.mode.rawValue, privacy: .public)")
        do {
            message = try await HealthSkillPushCoordinator.shared.pushHealthDashboard(
                mode: mode.domainMode,
                waitForFinalResult: false
            )
            Self.logger.info("健康推送成功：\(message, privacy: .public)")
        } catch {
            message = Self.errorMessage(for: error)
            Self.logger.error("健康推送失败：\(message, privacy: .public)")
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }

    private static func errorMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription, !description.isEmpty {
            return description
        }
        let fallback = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallback.isEmpty, fallback != "The operation couldn’t be completed." {
            return fallback
        }
        return "健康推送失败，请打开 App 检查健康授权与同步设备。"
    }
}

// 三个无参数包装：方便“健康看板 - 睡眠/健身/一日总结”出现在 Siri/快捷指令列表里。
struct HealthSleepPushIntent: AppIntent {
    static let title: LocalizedStringResource = "推送睡眠看板"
    static let description = IntentDescription("把昨晚睡眠看板推送到已绑定的墨水屏。")
    static let openAppWhenRun = false

    func perform() async -> some IntentResult & ProvidesDialog {
        await runHealthShortcut(mode: .sleep)
    }
}

struct HealthFitnessPushIntent: AppIntent {
    static let title: LocalizedStringResource = "推送健身看板"
    static let description = IntentDescription("把今日健身环数据看板推送到已绑定的墨水屏。")
    static let openAppWhenRun = false

    func perform() async -> some IntentResult & ProvidesDialog {
        await runHealthShortcut(mode: .fitness)
    }
}

struct HealthDailyPushIntent: AppIntent {
    static let title: LocalizedStringResource = "推送一日总结"
    static let description = IntentDescription("把今天的健康一日总结推送到已绑定的墨水屏。")
    static let openAppWhenRun = false

    func perform() async -> some IntentResult & ProvidesDialog {
        await runHealthShortcut(mode: .daily)
    }
}

private func runHealthShortcut(mode: HealthDashboardMode) async -> some IntentResult & ProvidesDialog {
    let message: String
    do {
        message = try await HealthSkillPushCoordinator.shared.pushHealthDashboard(
            mode: mode,
            waitForFinalResult: false
        )
    } catch {
        if let localized = error as? LocalizedError, let description = localized.errorDescription, !description.isEmpty {
            message = description
        } else {
            message = error.localizedDescription
        }
    }
    return .result(dialog: IntentDialog(stringLiteral: message))
}

// iOS 26 之后建议显式声明纯后台模式，避免被系统提升为 UI 进程。
@available(iOS 26.0, *)
extension HealthPushIntent {
    static var supportedModes: IntentModes { .background }
}

@available(iOS 26.0, *)
extension HealthSleepPushIntent {
    static var supportedModes: IntentModes { .background }
}

@available(iOS 26.0, *)
extension HealthFitnessPushIntent {
    static var supportedModes: IntentModes { .background }
}

@available(iOS 26.0, *)
extension HealthDailyPushIntent {
    static var supportedModes: IntentModes { .background }
}
