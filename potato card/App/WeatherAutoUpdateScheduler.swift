import BackgroundTasks
import Combine
import Foundation
import OSLog
import SwiftUI

@MainActor
final class WeatherAutoUpdateScheduler: ObservableObject {
    private enum Constants {
        static let taskIdentifier = "com.liyouliang.potatocard.weather-refresh"
        static let lastAttemptKey = "weatherAutoUpdateLastAttemptAt"
        static let minimumForegroundCheckInterval: TimeInterval = 5 * 60
    }

    private let logger = Logger(subsystem: "com.xiaogousi.online.potato-card", category: "WeatherAutoUpdate")
    private var foregroundLoopTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var didRegisterBackgroundTask = false

    init() {
        registerBackgroundTask()
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            startForegroundLoop()
            Task { await runIfDue(reason: "app-active") }
        case .inactive, .background:
            stopForegroundLoop()
            scheduleBackgroundRefresh()
        @unknown default:
            scheduleBackgroundRefresh()
        }
    }

    private func registerBackgroundTask() {
        guard !didRegisterBackgroundTask else { return }
        didRegisterBackgroundTask = true

        let didRegister = BGTaskScheduler.shared.register(forTaskWithIdentifier: Constants.taskIdentifier, using: nil) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            Task { @MainActor [weak self] in
                self?.handleBackgroundRefresh(refreshTask)
            }
        }

        if didRegister {
            logger.info("天气自动更新后台任务注册成功。")
            scheduleBackgroundRefresh()
        } else {
            logger.error("天气自动更新后台任务注册失败。")
        }
    }

    private func startForegroundLoop() {
        guard foregroundLoopTask == nil else { return }

        foregroundLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Constants.minimumForegroundCheckInterval * 1_000_000_000))
                await self?.runIfDue(reason: "foreground-loop")
            }
        }
    }

    private func stopForegroundLoop() {
        foregroundLoopTask?.cancel()
        foregroundLoopTask = nil
    }

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundRefresh()

        let updateTask = Task { [weak self] in
            guard let self else {
                task.setTaskCompleted(success: false)
                return
            }

            let success = await self.runIfDue(reason: "background-refresh")
            task.setTaskCompleted(success: success)
        }

        task.expirationHandler = {
            updateTask.cancel()
        }
    }

    @discardableResult
    private func runIfDue(reason: String) async -> Bool {
        guard updateTask == nil else {
            logger.info("天气自动更新跳过：已有更新任务正在运行。reason=\(reason, privacy: .public)")
            return true
        }

        let store = WeatherSkillStore()
        guard store.config.isEnabled else {
            logger.info("天气自动更新跳过：天气技能未开启。")
            return true
        }
        guard store.config.isAutoUpdateEnabled else {
            logger.info("天气自动更新跳过：自动更新未开启。")
            return true
        }
        guard store.config.hasCredentials else {
            logger.error("天气自动更新跳过：天气凭据缺失。")
            return false
        }
        guard store.config.targetDeviceSnapshot != nil || !store.config.targetDeviceID.trimmed.isEmpty else {
            logger.error("天气自动更新跳过：未选择同步设备。")
            return false
        }
        guard store.config.updateFrequency.supportsScheduledAutoUpdate else {
            logger.info("天气自动更新跳过：当前频率为\(store.config.updateFrequency.title, privacy: .public)，仅同步时更新。")
            return true
        }
        guard isDue(configuration: store.config) else {
            logger.info("天气自动更新跳过：未到更新频率。reason=\(reason, privacy: .public)")
            return true
        }

        recordAttemptNow()
        logger.info("天气自动更新开始：reason=\(reason, privacy: .public), frequency=\(store.config.updateFrequency.title, privacy: .public)")

        let task = Task { @MainActor in
            do {
                let message = try await WeatherSkillPushCoordinator.shared.startLatestWeatherPushFromShortcut()
                self.logger.info("天气自动更新已触发：\(message, privacy: .public)")
            } catch {
                self.logger.error("天气自动更新失败：\(error.localizedDescription, privacy: .public)")
            }
        }
        updateTask = task
        await task.value
        updateTask = nil
        return !task.isCancelled
    }

    private func isDue(configuration: WeatherSkillConfiguration) -> Bool {
        let interval = configuration.updateFrequency.automationInterval
        let lastDate = lastAttemptAt ?? configuration.lastSyncAt ?? .distantPast
        return Date().timeIntervalSince(lastDate) >= interval
    }

    private var lastAttemptAt: Date? {
        UserDefaults.standard.object(forKey: Constants.lastAttemptKey) as? Date
    }

    private func recordAttemptNow() {
        UserDefaults.standard.set(Date(), forKey: Constants.lastAttemptKey)
    }

    private func scheduleBackgroundRefresh() {
        let store = WeatherSkillStore()
        guard store.config.isEnabled, store.config.isAutoUpdateEnabled, store.config.hasCredentials else { return }
        // “同步时更新” 不产生后台刷新请求，避免浪费后台预算。
        guard store.config.updateFrequency.supportsScheduledAutoUpdate else {
            logger.info("天气自动更新后台任务未提交：当前频率为\(store.config.updateFrequency.title, privacy: .public)。")
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: Constants.taskIdentifier)
        request.earliestBeginDate = nextEarliestBeginDate(configuration: store.config)

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("天气自动更新后台任务已提交：earliest=\(request.earliestBeginDate?.description ?? "nil", privacy: .public)")
        } catch {
            logger.error("天气自动更新后台任务提交失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    private func nextEarliestBeginDate(configuration: WeatherSkillConfiguration) -> Date {
        let interval = configuration.updateFrequency.automationInterval
        let lastDate = lastAttemptAt ?? configuration.lastSyncAt ?? Date()
        let dueDate = lastDate.addingTimeInterval(interval)
        return max(Date().addingTimeInterval(15 * 60), dueDate)
    }
}

private extension WeatherUpdateFrequency {
    var automationInterval: TimeInterval {
        switch self {
        case .onSync:
            // 同步时更新不走定时逻辑，返回一个不会被 isDue 函数命中的超大间隔。
            return .greatestFiniteMagnitude
        case .hourly:
            return 60 * 60
        case .everyThreeHours:
            return 3 * 60 * 60
        case .daily:
            return 24 * 60 * 60
        }
    }
}
