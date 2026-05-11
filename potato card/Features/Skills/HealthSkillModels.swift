//
//  HealthSkillModels.swift
//  potato card
//
//  健康看板的领域模型：模式枚举、配置结构、运行时快照、错误描述。
//  目标设备复用天气技能的 WeatherTargetDeviceSnapshot（实际是一份通用墨水屏快照）。
//

import Foundation
import CoreGraphics

// 健康看板支持的三种模式。墨水屏屏幕较小，每个模式都聚焦一组指标。
enum HealthDashboardMode: String, Codable, CaseIterable, Identifiable {
    case sleep
    case fitness
    case daily

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep:
            return "睡眠看板"
        case .fitness:
            return "健身看板"
        case .daily:
            return "一日总结"
        }
    }

    var shortcutPhrase: String {
        switch self {
        case .sleep:
            return "睡眠"
        case .fitness:
            return "健身"
        case .daily:
            return "一日总结"
        }
    }

    var systemImage: String {
        switch self {
        case .sleep:
            return "moon.zzz.fill"
        case .fitness:
            return "figure.run"
        case .daily:
            return "sun.max.fill"
        }
    }

    var summary: String {
        switch self {
        case .sleep:
            return "总时长、入睡时间、深睡占比"
        case .fitness:
            return "活动能量、运动分钟、步数"
        case .daily:
            return "把一天的关键指标做汇总"
        }
    }
}

struct HealthSkillConfiguration: Codable, Equatable {
    // 健康看板默认关闭。开关由用户主动打开，第一次打开时才请求 HealthKit 授权。
    var isEnabled = false
    var defaultMode: HealthDashboardMode = .daily
    // 健康看板复用全局图像算法不太合适——墨水屏上文字密度更高，默认仍走 Bayer 8x8。
    var imageAlgorithm: EInkDitherAlgorithm = .bayer8x8
    var targetDeviceID = ""
    var targetDeviceSnapshot: WeatherTargetDeviceSnapshot?
    var lastSyncAt: Date?
    var lastSyncMode: HealthDashboardMode?
    // 用户拒绝授权时记一下，下次进设置不再自动弹权限请求。
    var didRequestAuthorization = false
    // 用户日常起床时间（24h 小时数）。
    // 「睡眠日」切分点 = 该时间 - 3 小时（一晚里可能的最早起床时间也归到当晚）。
    // 例：默认 7 → 切分点 04:00；用户 10 点起 → 切分点 07:00。
    var dailyWakeHour: Int = 7

    init() {}

    enum CodingKeys: String, CodingKey {
        case isEnabled, defaultMode, imageAlgorithm, targetDeviceID, targetDeviceSnapshot
        case lastSyncAt, lastSyncMode, didRequestAuthorization, dailyWakeHour
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        defaultMode = try c.decodeIfPresent(HealthDashboardMode.self, forKey: .defaultMode) ?? .daily
        imageAlgorithm = try c.decodeIfPresent(EInkDitherAlgorithm.self, forKey: .imageAlgorithm) ?? .bayer8x8
        targetDeviceID = try c.decodeIfPresent(String.self, forKey: .targetDeviceID) ?? ""
        targetDeviceSnapshot = try c.decodeIfPresent(WeatherTargetDeviceSnapshot.self, forKey: .targetDeviceSnapshot)
        lastSyncAt = try c.decodeIfPresent(Date.self, forKey: .lastSyncAt)
        lastSyncMode = try c.decodeIfPresent(HealthDashboardMode.self, forKey: .lastSyncMode)
        didRequestAuthorization = try c.decodeIfPresent(Bool.self, forKey: .didRequestAuthorization) ?? false
        dailyWakeHour = try c.decodeIfPresent(Int.self, forKey: .dailyWakeHour) ?? 7
    }
}

// 渲染层用到的睡眠数据：起止时间 + 各阶段时长 + 睡眠期间的生理指标。
struct HealthSleepSnapshot: Equatable {
    let bedtime: Date
    let wakeTime: Date
    let inBedDuration: TimeInterval
    let asleepDuration: TimeInterval
    let deepDuration: TimeInterval
    let remDuration: TimeInterval
    let coreDuration: TimeInterval
    let awakeDuration: TimeInterval
    // 睡眠期间生理指标，缺数据时为 nil，渲染层会显示 "—"。
    let averageHeartRate: Double?
    let minHeartRate: Double?
    let respiratoryRate: Double?
    let bloodOxygenAverage: Double?
    let heartRateVariability: Double?
    // 最近 7 个「睡眠日」的实际入睡时长（asleep），按时间正序，最新一天在末尾。
    // 没有数据的夜晚记为 0；用于「近 3 天 / 近 7 天 平均」摘要。
    let recentAsleepDurations: [TimeInterval]
}

// 综合算法：根据「睡眠时长 / 深睡占比 / REM 占比 / 清醒时长 / 平均心率」
// 给出一个 50~99 的睡眠评分，纯本地启发式，仅用于在墨水屏上给一个直观参考。
extension HealthSleepSnapshot {
    var sleepScore: Int {
        // 起步 99 分，逐项扣分；最终 clamp 到 [50, 99]。
        var score = 99.0

        // 1. 入睡时长：目标 ≥ 7h。每差 1h 扣 8 分；超过 10h 也扣（睡过头）。
        let asleepHours = asleepDuration / 3600
        if asleepHours < 7 {
            score -= (7 - asleepHours) * 8
        } else if asleepHours > 10 {
            score -= (asleepHours - 10) * 5
        }

        // 2. 深睡占比：目标 ≥ 13%。低于则按差距比例扣最多 12 分。
        if asleepDuration > 0 {
            let deepRatio = deepDuration / asleepDuration
            if deepRatio < 0.13 {
                score -= (0.13 - deepRatio) / 0.13 * 12
            }
        }

        // 3. REM 占比：目标 ≥ 18%。低于则按差距比例扣最多 8 分。
        if asleepDuration > 0 {
            let remRatio = remDuration / asleepDuration
            if remRatio < 0.18 {
                score -= (0.18 - remRatio) / 0.18 * 8
            }
        }

        // 4. 夜间清醒：超过 30 分钟开始线性扣分，最多扣 10 分（清醒 ≥ 90 分钟封顶）。
        let awakeMinutes = awakeDuration / 60
        if awakeMinutes > 30 {
            score -= min(10, (awakeMinutes - 30) / 60 * 10)
        }

        // 5. 平均心率：睡眠期间偏高（≥ 75 bpm）扣分。
        if let avg = averageHeartRate, avg >= 75 {
            score -= min(8, (avg - 75) / 5 * 4)
        }

        // 数据稀疏（睡眠 < 1h）直接给最低分，避免误导。
        if asleepDuration < 3600 { score = 50 }

        return Int(min(99.0, max(50.0, score)).rounded())
    }
}

struct HealthFitnessSnapshot: Equatable {
    let date: Date
    let activeEnergyKcal: Double
    let activeEnergyGoalKcal: Double?
    let exerciseMinutes: Double
    let exerciseGoalMinutes: Double?
    let standHours: Double
    let standGoalHours: Double?
    let stepCount: Int
    let distanceMeters: Double
    let workoutCount: Int
    let workoutDuration: TimeInterval
    // 今日身体指标，缺数据时 nil（看板里显示 "—"）。
    let restingHeartRate: Double?
    let averageHeartRate: Double?
    let respiratoryRate: Double?
    let bloodOxygenAverage: Double?
}

struct HealthDailySnapshot: Equatable {
    let date: Date
    let fitness: HealthFitnessSnapshot
    let sleep: HealthSleepSnapshot?
    let restingHeartRate: Double?
    let avgHeartRate: Double?
    let mindfulMinutes: Double
    // “总结”模块需要的趋势数据：今日体重 + 上周同期体重。两者都可能为 nil。
    let weightKg: Double?
    let weightKgLastWeek: Double?
}

struct HealthSnapshot: Equatable {
    let mode: HealthDashboardMode
    let updatedAt: Date
    let sleep: HealthSleepSnapshot?
    let fitness: HealthFitnessSnapshot?
    let daily: HealthDailySnapshot?

    static func sleep(_ value: HealthSleepSnapshot, updatedAt: Date = Date()) -> HealthSnapshot {
        HealthSnapshot(mode: .sleep, updatedAt: updatedAt, sleep: value, fitness: nil, daily: nil)
    }

    static func fitness(_ value: HealthFitnessSnapshot, updatedAt: Date = Date()) -> HealthSnapshot {
        HealthSnapshot(mode: .fitness, updatedAt: updatedAt, sleep: nil, fitness: value, daily: nil)
    }

    static func daily(_ value: HealthDailySnapshot, updatedAt: Date = Date()) -> HealthSnapshot {
        HealthSnapshot(mode: .daily, updatedAt: updatedAt, sleep: nil, fitness: nil, daily: value)
    }
}

enum HealthSkillLoadState: Equatable {
    case idle
    case missingAuthorization
    case loading
    case loaded
    case failed(String)

    var message: String {
        switch self {
        case .idle:
            return "等待刷新"
        case .missingAuthorization:
            return "请在健康 App 授权后再刷新"
        case .loading:
            return "正在读取健康数据"
        case .loaded:
            return "健康数据已更新"
        case .failed(let message):
            return message
        }
    }
}

enum HealthSkillError: LocalizedError {
    case healthDataUnavailable
    case authorizationDenied
    case noData(HealthDashboardMode)
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "当前设备不支持健康数据，无法生成健康看板。"
        case .authorizationDenied:
            return "未授权读取健康数据，请在健康 App 中允许后再试。"
        case .noData(let mode):
            return "暂时没有可用的\(mode.title)数据，戴上设备记录一段时间后再试。"
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}

extension Skill {
    static func health(summary: String, configuration: HealthSkillConfiguration) -> Skill {
        Skill(
            id: "health",
            title: "健康看板",
            isEnabled: configuration.isEnabled,
            lastSyncAt: configuration.lastSyncAt,
            previewSummary: summary
        )
    }
}
