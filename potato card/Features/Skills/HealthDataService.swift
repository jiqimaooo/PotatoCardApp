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
            // 睡眠看板会展示心率 / 呼吸 / 血氧 / HRV，这些都按 quantity type 读取。
            insertQuantity(into: &types, identifier: .heartRate)
            insertQuantity(into: &types, identifier: .respiratoryRate)
            insertQuantity(into: &types, identifier: .oxygenSaturation)
            insertQuantity(into: &types, identifier: .heartRateVariabilitySDNN)
        case .fitness:
            insertQuantity(into: &types, identifier: .activeEnergyBurned)
            insertQuantity(into: &types, identifier: .appleExerciseTime)
            // 站立时长（appleStandTime）按分钟累加，appleStandHour 是分类样本，按“小时计数”表达 Apple Watch 站立环的真实读数，两者都收。
            insertQuantity(into: &types, identifier: .appleStandTime)
            if let standHour = HKObjectType.categoryType(forIdentifier: .appleStandHour) {
                types.insert(standHour)
            }
            insertQuantity(into: &types, identifier: .stepCount)
            insertQuantity(into: &types, identifier: .distanceWalkingRunning)
            // 健身看板下半部分会展示心率/呼吸/血氧等身体指标，这些也按今日时间窗读。
            insertQuantity(into: &types, identifier: .heartRate)
            insertQuantity(into: &types, identifier: .restingHeartRate)
            insertQuantity(into: &types, identifier: .respiratoryRate)
            insertQuantity(into: &types, identifier: .oxygenSaturation)
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
            // 一日总结底部“总结”模块会拿体重和上一周对比，做趋势提示。
            insertQuantity(into: &types, identifier: .bodyMass)
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

    // 「睡眠日」按起床事件归属。切分点 = 用户日常起床时间 − 3 小时，可配置。
    // 比如默认起床 07:00 → 切分点 04:00；用户改成 10:00 起床 → 切分点 07:00。
    //
    // 分桶规则改用 session.startDate（一晚的开始时刻）：
    // 跨切分点的睡眠会自然落到「开始那天」的桶里，等价于产品需求里说的
    // 「如果某个睡眠包含了分割点，算作前一天」。
    //
    // sleepDayLowerBound(daysAgo: N) 返回 bucket[N] 的下边界（不含），是 splitHour 锚点；
    // bucket[N] 的上边界（含）：daysAgo=0 时是 now，否则是更近一天的同锚点。
    private func mostRecentSplitBefore(now: Date, splitHour: Int) -> Date {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let anchorToday = cal.date(byAdding: .hour, value: splitHour, to: startOfToday) ?? startOfToday
        if now >= anchorToday {
            return anchorToday
        }
        return cal.date(byAdding: .day, value: -1, to: anchorToday) ?? anchorToday
    }

    func sleepDayLowerBound(daysAgo: Int, now: Date = Date(), splitHour: Int = 4) -> Date {
        let cal = Calendar.current
        let anchor = mostRecentSplitBefore(now: now, splitHour: splitHour)
        return cal.date(byAdding: .day, value: -daysAgo, to: anchor) ?? anchor
    }

    func sleepDayUpperBound(daysAgo: Int, now: Date = Date(), splitHour: Int = 4) -> Date {
        guard daysAgo > 0 else { return now }
        return sleepDayLowerBound(daysAgo: daysAgo - 1, now: now, splitHour: splitHour)
    }

    func fetchSleepSnapshot(dailyWakeHour: Int = 7) async throws -> HealthSleepSnapshot {
        // 切分点 = 起床时间 − 3 小时，并 clamp 到 [0, 23]。
        let splitHour = max(0, min(23, dailyWakeHour - 3))
        return try await fetchSleepSnapshotImpl(splitHour: splitHour)
    }

    private func fetchSleepSnapshotImpl(splitHour: Int) async throws -> HealthSleepSnapshot {
        guard let store = healthStore else {
            throw HealthSkillError.healthDataUnavailable
        }
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthSkillError.noData(.sleep)
        }

        let now = Date()
        // 一次性把过去 7 个「睡眠日」拉下来。窗口起点再往前留 8 小时兜底，
        // 终点就是 now（包含「正在结束的当晚」起床事件）。
        let queryStart = Calendar.current.date(
            byAdding: .hour,
            value: -8,
            to: sleepDayLowerBound(daysAgo: 6, now: now, splitHour: splitHour)
        ) ?? now
        let queryEnd = now

        let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: queryEnd, options: .strictEndDate)

        let samples = try await querySamples(store: store, type: type, predicate: predicate)
        guard !samples.isEmpty else { throw HealthSkillError.noData(.sleep) }

        // 先把所有 sample 按时间正序分割成「睡眠会话」：相邻样本间隔 < 2 小时视作同一晚。
        // HealthKit 一晚会产出几十个子样本（深睡/REM/核心/清醒…），不能按单 sample 分桶。
        // 阈值放宽到 2 小时是为了把「夜里起来上厕所/喝水后再睡」这种短中断也算回同一晚的睡眠。
        let sortedByStart = samples.sorted { $0.startDate < $1.startDate }
        var sessions: [[HKCategorySample]] = []
        var currentSession: [HKCategorySample] = []
        var sessionMaxEnd: Date?
        for sample in sortedByStart {
            if let lastEnd = sessionMaxEnd, sample.startDate.timeIntervalSince(lastEnd) >= 2 * 60 * 60 {
                sessions.append(currentSession)
                currentSession = []
                sessionMaxEnd = nil
            }
            currentSession.append(sample)
            sessionMaxEnd = max(sessionMaxEnd ?? sample.endDate, sample.endDate)
        }
        if !currentSession.isEmpty {
            sessions.append(currentSession)
        }

        // 按 session.startDate 分桶（不是 endDate）。这样跨切分点的睡眠自然落到「开始那天」的桶里，
        // 等价于：「如果某个睡眠包含了分割点，算作前一天」。
        var buckets: [Int: [HKCategorySample]] = [:]
        let lowerBounds: [Date] = (0...7).map { sleepDayLowerBound(daysAgo: $0, now: now, splitHour: splitHour) }
        let upperBounds: [Date] = (0..<7).map { sleepDayUpperBound(daysAgo: $0, now: now, splitHour: splitHour) }
        for session in sessions {
            guard let startMin = session.map(\.startDate).min() else { continue }
            for n in 0..<7 where startMin > lowerBounds[n + 1] && startMin <= upperBounds[n] {
                // 多段 session 落到同一桶时（午睡 + 夜睡）合并，让总时长更接近真实。
                buckets[n, default: []].append(contentsOf: session)
                break
            }
        }

        // 计算每一晚的 effective 在床时长，组装成「recentAsleepDurations（最早→最新）」。
        // 这里改用 effectiveInBed（与顶部「总在床时长」同口径），而不是只算阶段化 asleep —
        // 否则缺少阶段标记的设备会让每晚平均只剩 3~5 小时，与用户实际体感不符。
        // 注意：只包含「实际有数据的夜晚」，没数据的夜晚是 0，渲染层 averageAsleepLabel
        // 会过滤 0 后再求平均（= 过去 7/3 天里"有数据的 y 天" 取平均）。
        var recentAsleepSeven: [TimeInterval] = []
        for n in stride(from: 6, through: 0, by: -1) {
            let stats = sessionStatistics(for: buckets[n] ?? [])
            recentAsleepSeven.append(stats.effectiveInBed)
        }

        // 最近一晚（daysAgo=0）拿来当作 snapshot 主体。
        let latestSamples = buckets[0] ?? []
        guard !latestSamples.isEmpty else {
            throw HealthSkillError.noData(.sleep)
        }
        let latest = sessionStatistics(for: latestSamples)
        guard let sessionStart = latest.start, let sessionEnd = latest.end else {
            throw HealthSkillError.noData(.sleep)
        }

        // 顶部「总在床时长」与 recentAsleepDurations 同口径：effective in-bed。
        let effectiveInBed = latest.effectiveInBed

        // 睡眠期间生理指标：复用同一时间窗，缺数据时返回 nil（看板里会显示 "—"）。
        let vitalsPredicate = HKQuery.predicateForSamples(withStart: sessionStart, end: sessionEnd, options: .strictStartDate)
        async let avgHR = averageQuantity(store: store, identifier: .heartRate, unit: HKUnit(from: "count/min"), predicate: vitalsPredicate)
        async let minHR = minQuantity(store: store, identifier: .heartRate, unit: HKUnit(from: "count/min"), predicate: vitalsPredicate)
        async let respRate = averageQuantity(store: store, identifier: .respiratoryRate, unit: HKUnit(from: "count/min"), predicate: vitalsPredicate)
        async let spo2 = averageQuantity(store: store, identifier: .oxygenSaturation, unit: HKUnit.percent(), predicate: vitalsPredicate)
        async let hrv = averageQuantity(store: store, identifier: .heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli), predicate: vitalsPredicate)

        let avgHRValue = await avgHR
        let minHRValue = await minHR
        let respValue = await respRate
        let spo2Value = await spo2
        let hrvValue = await hrv

        return HealthSleepSnapshot(
            bedtime: sessionStart,
            wakeTime: sessionEnd,
            inBedDuration: effectiveInBed,
            asleepDuration: latest.asleep,
            deepDuration: latest.deep,
            remDuration: latest.rem,
            coreDuration: latest.core,
            awakeDuration: latest.awake,
            averageHeartRate: avgHRValue,
            minHeartRate: minHRValue,
            respiratoryRate: respValue,
            // HealthKit 的 oxygenSaturation 单位是百分比（0~1），转成 0~100 方便渲染层处理。
            bloodOxygenAverage: spo2Value.map { $0 * 100 },
            heartRateVariability: hrvValue,
            recentAsleepDurations: recentAsleepSeven
        )
    }

    // 把一晚的 HKCategorySample 数组折叠成阶段时长 + 起止时间。
    private struct SleepSessionStats {
        var inBed: TimeInterval = 0
        var asleep: TimeInterval = 0
        var deep: TimeInterval = 0
        var rem: TimeInterval = 0
        var core: TimeInterval = 0
        var awake: TimeInterval = 0
        var start: Date?
        var end: Date?

        // 顶部「总在床时长」的口径：直接用 session 整段跨度（first start → last end），
        // 不再读 .inBed 字段。原因：Apple Watch 的 .inBed 只在检测到长时间静止时记录，
        // 经常只覆盖真实在床时间的一部分；用 max(inBed, span) 也不准，因为 span 才是
        // 「从上床到起床」的真实时长，与用户体感一致。无 sample 时退到 .asleep 防 0。
        var effectiveInBed: TimeInterval {
            if let start, let end {
                let span = end.timeIntervalSince(start)
                if span > 0 { return span }
            }
            if inBed > 0 { return inBed }
            return asleep
        }
    }

    private func sessionStatistics(for samples: [HKCategorySample]) -> SleepSessionStats {
        guard !samples.isEmpty else { return SleepSessionStats() }
        let sorted = samples.sorted { $0.startDate < $1.startDate }

        // 选「最后一个 endDate 所属的连续会话」：从最后一个样本往前回溯，相邻间隔 < 2 小时视为同一晚。
        // 与 fetchSleepSnapshotImpl 里的分段阈值保持一致，避免两处口径漂移。
        guard let last = sorted.last else { return SleepSessionStats() }
        var session: [HKCategorySample] = [last]
        var pointer = last.startDate
        for sample in sorted.reversed().dropFirst() {
            if pointer.timeIntervalSince(sample.endDate) < 2 * 60 * 60 {
                session.append(sample)
                pointer = min(pointer, sample.startDate)
            } else {
                break
            }
        }
        session.reverse()

        var stats = SleepSessionStats()
        for sample in session {
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            case .inBed:
                stats.inBed += duration
            case .asleepDeep:
                stats.deep += duration
                stats.asleep += duration
            case .asleepREM:
                stats.rem += duration
                stats.asleep += duration
            case .asleepCore:
                stats.core += duration
                stats.asleep += duration
            case .asleepUnspecified:
                stats.asleep += duration
            case .awake:
                stats.awake += duration
            default:
                break
            }
        }
        stats.start = session.first?.startDate
        stats.end = session.last?.endDate
        return stats
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
        // 站立小时：优先用 appleStandHour 分类样本（与 Apple Watch 三环一致），
        // 没有这份数据再回退到 appleStandTime（分钟累加）。
        async let standHoursFromCategory = countStandHours(store: store, predicate: predicate)
        async let standMinutesQuantity = sumQuantity(store: store, identifier: .appleStandTime, unit: .minute(), predicate: predicate)
        async let stepCount = sumQuantity(store: store, identifier: .stepCount, unit: .count(), predicate: predicate)
        async let distance = sumQuantity(store: store, identifier: .distanceWalkingRunning, unit: .meter(), predicate: predicate)
        async let workouts = fetchWorkouts(store: store, predicate: predicate)
        async let summary = fetchActivitySummary(store: store)

        // 今日身体指标：静息心率取最新一次记录（不限今天），其余三个按今日时间窗的平均。
        let bpmUnit = HKUnit(from: "count/min")
        async let restingHRValue = latestSampleValue(store: store, identifier: .restingHeartRate, unit: bpmUnit)
        async let avgHRValue = averageQuantity(store: store, identifier: .heartRate, unit: bpmUnit, predicate: predicate)
        async let respiratoryValue = averageQuantity(store: store, identifier: .respiratoryRate, unit: bpmUnit, predicate: predicate)
        async let spo2Value = averageQuantity(store: store, identifier: .oxygenSaturation, unit: HKUnit.percent(), predicate: predicate)

        let energyValue = await activeEnergy
        let exerciseValue = await exerciseMinutes
        let standCategoryHours = await standHoursFromCategory
        let standMinutes = await standMinutesQuantity
        let stepsValue = await stepCount
        let distanceValue = await distance
        let workoutList = await workouts
        let summaryValue = await summary
        let restingHR = await restingHRValue
        let avgHR = await avgHRValue
        let resp = await respiratoryValue
        let spo2 = await spo2Value

        let workoutDuration = workoutList.reduce(0.0) { $0 + $1.duration }
        // 取“分类小时计数”和“分钟换算小时”里较大的那个，避免 appleStandHour 在部分设备未被记录时漏算。
        let standHoursValue = max(Double(standCategoryHours), standMinutes / 60.0)

        // 即便所有数值都是 0（例如刚授权完、当天还没开始活动），也返回一份零值快照，
        // 让看板能展示「今天还没动」而不是退回到通用占位图。

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
            workoutDuration: workoutDuration,
            restingHeartRate: restingHR,
            averageHeartRate: avgHR,
            respiratoryRate: resp,
            // HealthKit 的 oxygenSaturation 单位是百分比（0~1），转成 0~100 与睡眠看板保持一致。
            bloodOxygenAverage: spo2.map { $0 * 100 }
        )
    }

    // MARK: - 一日总结

    func fetchDailySnapshot(dailyWakeHour: Int = 7) async throws -> HealthDailySnapshot {
        guard let store = healthStore else { throw HealthSkillError.healthDataUnavailable }

        // fitness 是一日总结的主表，没有它直接抛 noData。
        let fitness = try await fetchFitnessSnapshot()

        // 睡眠数据可能缺失（比如午休还没记录），用 try? 容错。
        let sleep = try? await fetchSleepSnapshot(dailyWakeHour: dailyWakeHour)

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        async let restingHR = latestSampleValue(store: store, identifier: .restingHeartRate, unit: HKUnit(from: "count/min"))
        async let avgHR = averageQuantity(store: store, identifier: .heartRate, unit: HKUnit(from: "count/min"), predicate: predicate)
        async let mindful = sumCategoryDuration(store: store, identifier: .mindfulSession, predicate: predicate)

        // 体重 + 上周末同期体重，做趋势对比给“总结”模块用。
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        async let bodyMassNow = latestSampleValue(store: store, identifier: .bodyMass, unit: HKUnit.gramUnit(with: .kilo))
        async let bodyMassWeekAgo = latestSampleValue(
            store: store,
            identifier: .bodyMass,
            unit: HKUnit.gramUnit(with: .kilo),
            before: weekAgo
        )

        let resting = await restingHR
        let avg = await avgHR
        let mindfulValue = await mindful / 60.0 // 秒 → 分钟
        let weight = await bodyMassNow
        let weightLastWeek = await bodyMassWeekAgo

        return HealthDailySnapshot(
            date: now,
            fitness: fitness,
            sleep: sleep,
            restingHeartRate: resting,
            avgHeartRate: avg,
            mindfulMinutes: mindfulValue,
            weightKg: weight,
            weightKgLastWeek: weightLastWeek
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

    private func minQuantity(store: HKHealthStore, identifier: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteMin) { _, statistics, _ in
                let value = statistics?.minimumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func latestSampleValue(store: HKHealthStore, identifier: HKQuantityTypeIdentifier, unit: HKUnit, before: Date? = nil) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate: NSPredicate? = before.map { HKQuery.predicateForSamples(withStart: nil, end: $0, options: []) }
        return await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    // 统计 appleStandHour 分类样本里“已站立”状态的个数。对应 Apple Watch 三环里的站立环刻度。
    private func countStandHours(store: HKHealthStore, predicate: NSPredicate) async -> Int {
        guard let type = HKObjectType.categoryType(forIdentifier: .appleStandHour) else { return 0 }
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let categorySamples = (samples as? [HKCategorySample]) ?? []
                let stoodCount = categorySamples.reduce(0) { count, sample in
                    // HKCategoryValueAppleStandHour.stood == 0
                    sample.value == HKCategoryValueAppleStandHour.stood.rawValue ? count + 1 : count
                }
                continuation.resume(returning: stoodCount)
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
