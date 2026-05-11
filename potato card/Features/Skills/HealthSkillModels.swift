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

    init() {}
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
