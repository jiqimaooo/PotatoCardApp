//
//  HealthDataService.swift
//  potato card
//
//  HealthKit 数据读取服务。
//  - 按看板模式申请最小化的读权限，避免一次性请求所有指标。
//  - 抓取“最近一晚睡眠 / 今日健身环 / 今日总结”三套结构化数据。
//
//  注意：HealthKit 在 iOS 真机上才有真实数据。模拟器可以请求权限但读不出数据。
//  所有读取方法在「没有任何数据」时会抛出 HealthSkillError.noData，由调用方决定 UI 提示。
//

import Foundation
import HealthKit

// HealthKit 调用都跳出 MainActor，避免阻塞 UI。
final class HealthDataService: @unchecked Sendable {
    static let shared = HealthDataService()

    let healthStore: HKHealthStore?

    init() {
        if HKHealthStore.isHealthDataAvailable() {
            healthStore = HKHealthStore()
        } else {
            healthStore = nil
        }
    }

    var isAvailable: Bool {
        healthStore != nil
    }

    // 按模式构造对应的读权限集合。再叠加“全部”模式时取并集。
    func readTypes(for mode: HealthDashboardMode) -> Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        switch mode {
        case .sleep:
            if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
                types.insert(sleep)
            }
        case .fitness:
            insertQuantity(into: &types, identifier: .activeEnergyBurned)
            insertQuantity(into: &types, identifier: .appleExerciseTime)
            insertQuantity(into: &types, identifier: .appleStandTime)
            insertQuantity(into: &types, identifier: .stepCount)
            insertQuantity(into: &types, identifier: .distanceWalkingRunning)
            types.insert(HKObjectType.workoutType())
            if #available(iOS 16.0, *) {
                types.insert(HKObjectType.activitySummaryType())
            }
        case .daily:
            // 一日总结同时需要睡眠和健身的数据。
            types.formUnion(readTypes(for: .sleep))
            types.formUnion(readTypes(for: .fitness))
            insertQuantity(into: &types, identifier: .heartRate)
            insertQuantity(into: &types, identifier: .restingHeartRate)
            if let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
                types.insert(mindful)
            }
        }
        return types
    }

    // 多模式合集，用于一次性弹一次系统授权弹窗。
    func allReadTypes() -> Set<HKObjectType> {
        HealthDashboardMode.allCases.reduce(into: Set<HKObjectType>()) { acc, mode in
            acc.formUnion(readTypes(for: mode))
        }
    }

    func requestAuthorization(for mode: HealthDashboardMode) async throws {
        guard let store = healthStore else { throw HealthSkillError.healthDataUnavailable }
        let readTypes = readTypes(for: mode)
        guard !readTypes.isEmpty else { return }
        // HealthKit 不允许查询单个 type 的授权状态用于读取（仅写入），所以仅靠抛错来判断。
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func requestAuthorizationForAllModes() async throws {
        guard let store = healthStore else { throw HealthSkillError.healthDataUnavailable }
        let readTypes = allReadTypes()
        guard !readTypes.isEmpty else { return }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    private func insertQuantity(into types: inout Set<HKObjectType>, identifier: HKQuantityTypeIdentifier) {
        if let type = HKObjectType.quantityType(forIdentifier: identifier) {
            types.insert(type)
        }
    }

    // MARK: - 睡眠

    // 取“最近一晚”：从昨日 18:00 到今日 18:00 的睡眠分析样本。
    // HealthKit 的 sleepAnalysis 包含床上/各睡眠阶段；用 endDate 最大的样本块作为“起床时间”。
    func fetchSleepSnapshot() async throws -> HealthSleepSnapshot {
        guard let store = healthStore else { throw HealthSkillError.healthDataUnavailable }
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthSkillError.noData(.sleep)
        }

        let calendar = Calendar.current
        let now = Date()
        // 起止区间宽一点，覆盖晚归和早起的极端情况。
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let queryStart = calendar.date(byAdding: .hour, value: 12, to: startOfYesterday) ?? startOfYesterday
        let queryEnd = now

        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: queryEnd, options: .strictStartDate)

        let samples = try await querySamples(store: store, type: type, predicate: predicate)
        guard !samples.isEmpty else { throw HealthSkillError.noData(.sleep) }

        // 取 endDate 最晚的样本所属的“连续睡眠会话”：以最后一个样本为锚点向前回溯，
        // 中间间隔超过 45 分钟视为离开睡眠。
        let sorted = samples.sorted { $0.endDate < $1.endDate }
        guard let lastSample = sorted.last else { throw HealthSkillError.noData(.sleep) }

        var session: [HKCategorySample] = [lastSample]
        var pointer = lastSample.startDate
        for sample in sorted.reversed().dropFirst() {
            if pointer.timeIntervalSince(sample.endDate) <= 45 * 60 {
                session.append(sample)
                pointer = min(pointer, sample.startDate)
            } else {
                break
            }
        }
        session.reverse()

        var inBed: TimeInterval = 0
        var asleep: TimeInterval = 0
        var deep: TimeInterval = 0
        var rem: TimeInterval = 0
        var core: TimeInterval = 0
        var awake: TimeInterval = 0

        for sample in session {
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            // 不同 iOS 版本枚举值的命名变化用 rawValue 处理。
            switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            case .inBed:
                inBed += duration
            case .asleepDeep:
                deep += duration
                asleep += duration
            case .asleepREM:
                rem += duration
                asleep += duration
            case .asleepCore:
                core += duration
                asleep += duration
            case .asleepUnspecified:
                asleep += duration
            case .awake:
                awake += duration
            default:
                break
            }
        }

        guard let sessionStart = session.first?.startDate,
              let sessionEnd = session.last?.endDate else {
            throw HealthSkillError.noData(.sleep)
        }

        // inBed 为 0 时回退到 session 实际跨度，保证 UI 总时长一定有数。
        let fallbackInBed = sessionEnd.timeIntervalSince(sessionStart)
        let effectiveInBed = inBed > 0 ? inBed : fallbackInBed

        return HealthSleepSnapshot(
            bedtime: sessionStart,
            wakeTime: sessionEnd,
            inBedDuration: effectiveInBed,
            asleepDuration: asleep,
            deepDuration: deep,
            remDuration: rem,
            coreDuration: core,
            awakeDuration: awake
        )
    }

    // MARK: - 健身

    func fetchFitnessSnapshot() async throws -> HealthFitnessSnapshot {
        guard let store = healthStore else { throw HealthSkillError.healthDataUnavailable }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        async let activeEnergy = sumQuantity(store: store, identifier: .activeEnergyBurned, unit: .kilocalorie(), predicate: predicate)
        async let exerciseMinutes = sumQuantity(store: store, identifier: .appleExerciseTime, unit: .minute(), predicate: predicate)
        async let standHours = sumQuantity(store: store, identifier: .appleStandTime, unit: .minute(), predicate: predicate)
        async let stepCount = sumQuantity(store: store, identifier: .stepCount, unit: .count(), predicate: predicate)
        async let distance = sumQuantity(store: store, identifier: .distanceWalkingRunning, unit: .meter(), predicate: predicate)
        async let workouts = fetchWorkouts(store: store, predicate: predicate)
        async let summary = fetchActivitySummary(store: store)

        let energyValue = await activeEnergy
        let exerciseValue = await exerciseMinutes
        let standMinutes = await standHours
        let stepsValue = await stepCount
        let distanceValue = await distance
        let workoutList = await workouts
        let summaryValue = await summary

        let workoutDuration = workoutList.reduce(0.0) { $0 + $1.duration }
        let standHoursValue = standMinutes / 60.0

        let hasAnyData = energyValue > 0 || exerciseValue > 0 || stepsValue > 0 || distanceValue > 0 || workoutList.count > 0
        guard hasAnyData else { throw HealthSkillError.noData(.fitness) }

        return HealthFitnessSnapshot(
            date: now,
            activeEnergyKcal: energyValue,
            activeEnergyGoalKcal: summaryValue?.energyGoal,
            exerciseMinutes: exerciseValue,
            exerciseGoalMinutes: summaryValue?.exerciseGoal,
            standHours: standHoursValue,
            standGoalHours: summaryValue?.standGoal,
            stepCount: Int(stepsValue.rounded()),
            distanceMeters: distanceValue,
            workoutCount: workoutList.count,
            workoutDuration: workoutDuration
        )
    }

    // MARK: - 一日总结

    func fetchDailySnapshot() async throws -> HealthDailySnapshot {
        guard let store = healthStore else { throw HealthSkillError.healthDataUnavailable }

        // fitness 是一日总结的主表，没有它直接抛 noData。
        let fitness = try await fetchFitnessSnapshot()

        // 睡眠数据可能缺失（比如午休还没记录），用 try? 容错。
        let sleep = try? await fetchSleepSnapshot()

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        async let restingHR = latestSampleValue(store: store, identifier: .restingHeartRate, unit: HKUnit(from: "count/min"))
        async let avgHR = averageQuantity(store: store, identifier: .heartRate, unit: HKUnit(from: "count/min"), predicate: predicate)
        async let mindful = sumCategoryDuration(store: store, identifier: .mindfulSession, predicate: predicate)

        let resting = await restingHR
        let avg = await avgHR
        let mindfulValue = await mindful / 60.0 // 秒 → 分钟

        return HealthDailySnapshot(
            date: now,
            fitness: fitness,
            sleep: sleep,
            restingHeartRate: resting,
            avgHeartRate: avg,
            mindfulMinutes: mindfulValue
        )
    }

    // MARK: - 私有：HealthKit 查询封装

    private func querySamples(store: HKHealthStore, type: HKSampleType, predicate: NSPredicate) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, results, error in
                if let error = error {
                    continuation.resume(throwing: HealthSkillError.underlying(error))
                    return
                }
                let categorySamples = (results as? [HKCategorySample]) ?? []
                continuation.resume(returning: categorySamples)
            }
            store.execute(query)
        }
    }

    private func sumQuantity(store: HKHealthStore, identifier: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func averageQuantity(store: HKHealthStore, identifier: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, statistics, _ in
                let value = statistics?.averageQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func latestSampleValue(store: HKHealthStore, identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func sumCategoryDuration(store: HKHealthStore, identifier: HKCategoryTypeIdentifier, predicate: NSPredicate) async -> Double {
        guard let type = HKObjectType.categoryType(forIdentifier: identifier) else { return 0 }
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let duration = (samples ?? []).reduce(0.0) { acc, sample in
                    acc + sample.endDate.timeIntervalSince(sample.startDate)
                }
                continuation.resume(returning: duration)
            }
            store.execute(query)
        }
    }

    private func fetchWorkouts(store: HKHealthStore, predicate: NSPredicate) async -> [HKWorkout] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
    }

    private struct ActivityGoalValues {
        let energyGoal: Double?
        let exerciseGoal: Double?
        let standGoal: Double?
    }

    // iOS 16+ 才能拿到完整环目标。失败时返回 nil，UI 端自动隐藏环外圈。
    private func fetchActivitySummary(store: HKHealthStore) async -> ActivityGoalValues? {
        guard #available(iOS 16.0, *) else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        var startComponents = components
        startComponents.calendar = calendar
        var endComponents = components
        endComponents.calendar = calendar
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: startComponents, end: endComponents)

        return await withCheckedContinuation { continuation in
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                guard let summary = summaries?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                let energyUnit = HKUnit.kilocalorie()
                let minuteUnit = HKUnit.minute()
                let hourUnit = HKUnit.count()
                let energyGoal = summary.activeEnergyBurnedGoal.doubleValue(for: energyUnit)
                let exerciseGoal = summary.appleExerciseTimeGoal.doubleValue(for: minuteUnit)
                // 站立目标是“小时数”，按 count 计；HKUnit.count() 是其原生单位。
                let standGoal = summary.appleStandHoursGoal.doubleValue(for: hourUnit)
                continuation.resume(returning: ActivityGoalValues(
                    energyGoal: energyGoal > 0 ? energyGoal : nil,
                    exerciseGoal: exerciseGoal > 0 ? exerciseGoal : nil,
                    standGoal: standGoal > 0 ? standGoal : nil
                ))
            }
            store.execute(query)
        }
    }
}
