import BackgroundTasks
import Combine
import Foundation
import OSLog
import SwiftUI

@MainActor
final class WeatherAutoUpdateScheduler: ObservableObject {
    fileprivate enum Constants {
        nonisolated static let taskIdentifier = "com.liyouliang.potatocard.weather-refresh"
        nonisolated static let lastAttemptKey = "weatherAutoUpdateLastAttemptAt"
        nonisolated static let minimumForegroundCheckInterval: TimeInterval = 5 * 60
    }

    private let logger = Logger(subsystem: "com.xiaogousi.online.potato-card", category: "WeatherAutoUpdate")
    private var foregroundLoopTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?

    // 单例入口。在 PotatoCardApp.init 里预热使用，以便 BG task handler 能找到同一个实例。
    @MainActor static let shared = WeatherAutoUpdateScheduler()

    private init() {}

    // 必须在 application(_:didFinishLaunching*) 返回前调用，
    // 否则 BGTaskScheduler 会抛 NSInternalInconsistencyException。
    // 调用点：PotatoCardApp.init()。
    nonisolated static func registerBackgroundTaskIfNeeded() {
        Self.registerBackgroundTaskOnce.run()
    }

    fileprivate func handleBackgroundRefreshFromScheduler(_ task: BGAppRefreshTask) {
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
        // 保留实例方法避免外部调用点报错。真正的注册走 registerBackgroundTaskIfNeeded。
        WeatherAutoUpdateScheduler.registerBackgroundTaskIfNeeded()
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

extension WeatherAutoUpdateScheduler {
    // 一次性注册容器：BGTaskScheduler.register 只能在 app finishLaunching 之前调用一次。
    // 用 dispatch_once 等价的 NSLock + Bool flag 保证幂等，且支持 nonisolated 调用（@main App init 是 nonisolated）。
    final class Once {
        nonisolated private let lock = NSLock()
        nonisolated(unsafe) private var didRun = false

        nonisolated init() {}

        nonisolated func run() {
            lock.lock()
            defer { lock.unlock() }
            guard !didRun else { return }
            didRun = true

            let didRegister = BGTaskScheduler.shared.register(
                forTaskWithIdentifier: Constants.taskIdentifier,
                using: nil
            ) { task in
                guard let refreshTask = task as? BGAppRefreshTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                Task { @MainActor in
                    WeatherAutoUpdateScheduler.shared.handleBackgroundRefreshFromScheduler(refreshTask)
                }
            }
            ShortcutDebugLog.log("WeatherAutoUpdate", "BGTaskScheduler register didRegister=\(didRegister)")
        }
    }

    nonisolated static let registerBackgroundTaskOnce = Once()
}
