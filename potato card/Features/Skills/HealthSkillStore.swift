//
//  HealthSkillStore.swift
//  potato card
//
//  健康看板的运行时状态：配置持久化、权限请求、各模式快照刷新。
//  与天气技能一致，只读 + 单一可信源；快捷指令也通过这个 store 拉数据。
//

import Combine
import Foundation

@MainActor
final class HealthSkillStore: ObservableObject {
    private enum Constants {
        static let configurationKey = "healthSkillConfiguration"
    }

    @Published private(set) var config: HealthSkillConfiguration
    @Published private(set) var snapshot: HealthSnapshot?
    @Published private(set) var loadState: HealthSkillLoadState = .idle

    private let service = HealthDataService.shared
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    // 专用的后台串行队列，避免 JSON encode + UserDefaults 写入挤占主线程，
    // 让 picker / toggle 等 UI 操作能立刻返回。
    private static let persistQueue = DispatchQueue(label: "health.skill.store.persist", qos: .utility)

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.config = Self.loadConfiguration(decoder: JSONDecoder(), userDefaults: userDefaults)
    }

    var skill: Skill {
        let summary: String
        if let snapshot {
            summary = Self.summary(for: snapshot)
        } else {
            summary = config.defaultMode.summary
        }
        return .health(summary: summary, configuration: config)
    }

    var isHealthDataAvailable: Bool {
        service.isAvailable
    }

    // 进入设置页时调用一次，避免首次开关报无授权错误。
    func onAppear() async {
        guard service.isAvailable else {
            loadState = .failed(HealthSkillError.healthDataUnavailable.localizedDescription)
            return
        }
        // 第一次进入主动请求一次合集授权，之后只读取。用户取消授权也不再骚扰。
        if !config.didRequestAuthorization {
            await requestAuthorization()
        }
    }

    func updateEnabled(_ isEnabled: Bool) {
        config.isEnabled = isEnabled
        persistConfiguration()
        if isEnabled {
            // 开启技能时主动请求权限，与天气“同步时更新”体验一致。
            Task { await requestAuthorization() }
        }
    }

    func updateDefaultMode(_ mode: HealthDashboardMode) {
        config.defaultMode = mode
        persistConfiguration()
    }

    func updateDailyWakeHour(_ hour: Int) {
        config.dailyWakeHour = max(0, min(23, hour))
        persistConfiguration()
    }

    func updateImageAlgorithm(_ algorithm: EInkDitherAlgorithm) {
        config.imageAlgorithm = algorithm
        persistConfiguration()
    }

    func updateTargetDeviceID(_ deviceID: String) {
        config.targetDeviceID = deviceID
        if config.targetDeviceSnapshot?.id != deviceID {
            config.targetDeviceSnapshot = nil
        }
        persistConfiguration()
    }

    func updateTargetDevice(_ device: BleDevice) {
        config.targetDeviceID = device.id
        config.targetDeviceSnapshot = device.targetSnapshot
        persistConfiguration()
    }

    func updateTargetDeviceSnapshot(_ snapshot: WeatherTargetDeviceSnapshot) {
        config.targetDeviceID = snapshot.id
        config.targetDeviceSnapshot = snapshot
        persistConfiguration()
    }

    // 主动触发授权弹窗，写到 config 标记已请求过。
    func requestAuthorization() async {
        do {
            try await service.requestAuthorizationForAllModes()
            config.didRequestAuthorization = true
            persistConfiguration()
            if loadState == .missingAuthorization {
                loadState = .idle
            }
        } catch {
            // HealthKit 抛错通常是权限或不支持。
            loadState = .failed(error.localizedDescription)
        }
    }

    func refresh(mode: HealthDashboardMode? = nil) async {
        // 进入详情页查看数据不应被「开关 / 推送启用」挡住，开关只控制
        // 后台同步和推送行为。这里把 isEnabled 守卫去掉，让用户授权后
        // 一定能在 UI 上看到当前 HealthKit 真实数据（或一份空态）。
        guard service.isAvailable else {
            loadState = .failed(HealthSkillError.healthDataUnavailable.localizedDescription)
            return
        }

        let targetMode = mode ?? config.defaultMode
        let dailyWakeHour = config.dailyWakeHour
        loadState = .loading
        do {
            switch targetMode {
            case .sleep:
                let value = try await service.fetchSleepSnapshot(dailyWakeHour: dailyWakeHour)
                snapshot = .sleep(value)
            case .fitness:
                let value = try await service.fetchFitnessSnapshot()
                snapshot = .fitness(value)
            case .daily:
                let value = try await service.fetchDailySnapshot(dailyWakeHour: dailyWakeHour)
                snapshot = .daily(value)
            }
            loadState = .loaded
        } catch let HealthSkillError.noData(noDataMode) {
            // 真的没数据时，构造一个对应模式的空 snapshot，让 renderer 走
            // mode-specific 空态（"尚未读到最近一晚的睡眠数据" / "今日还没动" 等），
            // 而不是回到通用占位图。
            snapshot = HealthSnapshot(
                mode: noDataMode,
                updatedAt: Date(),
                sleep: nil,
                fitness: nil,
                daily: nil
            )
            loadState = .failed(HealthSkillError.noData(noDataMode).localizedDescription)
        } catch {
            // HealthKit 授权未通过时通常表现为没有数据可读。
            loadState = .failed(error.localizedDescription)
        }
    }

    func markSynced(mode: HealthDashboardMode) {
        config.lastSyncAt = Date()
        config.lastSyncMode = mode
        persistConfiguration()
    }

    private func persistConfiguration() {
        // 同样把 JSON encode + UserDefaults 写入给到后台串行队列，
        // 避免 picker / toggle 类 UI 操作同步阻塞主线程。
        let snapshot = config
        Self.persistQueue.async { [encoder, userDefaults] in
            guard let data = try? encoder.encode(snapshot) else { return }
            userDefaults.set(data, forKey: Constants.configurationKey)
        }
    }

    private static func loadConfiguration(decoder: JSONDecoder, userDefaults: UserDefaults) -> HealthSkillConfiguration {
        guard
            let data = userDefaults.data(forKey: Constants.configurationKey),
            let configuration = try? decoder.decode(HealthSkillConfiguration.self, from: data)
        else {
            return HealthSkillConfiguration()
        }
        return configuration
    }

    // 看板卡片预览文案。
    private static func summary(for snapshot: HealthSnapshot) -> String {
        switch snapshot.mode {
        case .sleep:
            guard let sleep = snapshot.sleep else { return HealthDashboardMode.sleep.summary }
            let hours = Int(sleep.inBedDuration / 3600)
            let minutes = Int((sleep.inBedDuration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "昨晚\(hours)h\(minutes)m"
        case .fitness:
            guard let fitness = snapshot.fitness else { return HealthDashboardMode.fitness.summary }
            return "今日\(Int(fitness.activeEnergyKcal.rounded()))kcal · \(fitness.stepCount)步"
        case .daily:
            guard let daily = snapshot.daily else { return HealthDashboardMode.daily.summary }
            return "今日\(Int(daily.fitness.activeEnergyKcal.rounded()))kcal · \(daily.fitness.stepCount)步"
        }
    }
}
