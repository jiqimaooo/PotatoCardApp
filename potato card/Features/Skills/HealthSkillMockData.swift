//
//  HealthSkillMockData.swift
//  potato card
//
//  仅用于本地预览/截图：当 HealthKit 拿不到数据时（模拟器、首次安装等），
//  把渲染层喂入一份可读的假数据，方便检查布局是否溢出、视觉是否合理。
//  正式构建里也会包含，但只有调试 UI 主动调用才会出现。
//

import Foundation

enum HealthSkillMockData {
    static let sleep: HealthSleepSnapshot = {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let bedtime = calendar.date(byAdding: .minute, value: -60, to: startOfDay) ?? now
        let wakeTime = calendar.date(byAdding: .hour, value: 7, to: startOfDay) ?? now
        return HealthSleepSnapshot(
            bedtime: bedtime,
            wakeTime: wakeTime,
            inBedDuration: 8 * 3600,
            asleepDuration: 7 * 3600 + 20 * 60,
            deepDuration: 1 * 3600 + 25 * 60,
            remDuration: 1 * 3600 + 40 * 60,
            coreDuration: 4 * 3600 + 5 * 60,
            awakeDuration: 30 * 60,
            averageHeartRate: 58,
            minHeartRate: 52,
            respiratoryRate: 14.6,
            bloodOxygenAverage: 97.4,
            heartRateVariability: 48
        )
    }()

    static let fitness = HealthFitnessSnapshot(
        date: Date(),
        activeEnergyKcal: 312,
        activeEnergyGoalKcal: 500,
        exerciseMinutes: 22,
        exerciseGoalMinutes: 30,
        standHours: 9,
        standGoalHours: 12,
        stepCount: 7423,
        distanceMeters: 5482,
        workoutCount: 1,
        workoutDuration: 32 * 60
    )

    static let daily = HealthDailySnapshot(
        date: Date(),
        fitness: fitness,
        sleep: sleep,
        restingHeartRate: 56,
        avgHeartRate: 78,
        mindfulMinutes: 10,
        weightKg: 62.4,
        weightKgLastWeek: 62.9
    )

    static func snapshot(for mode: HealthDashboardMode) -> HealthSnapshot {
        switch mode {
        case .sleep: return .sleep(sleep)
        case .fitness: return .fitness(fitness)
        case .daily: return .daily(daily)
        }
    }
}
