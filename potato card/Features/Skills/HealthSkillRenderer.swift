//
//  HealthSkillRenderer.swift
//  potato card
//
//  健康看板的 400x600 像素渲染器。
//  - 三种模式：睡眠 / 健身 / 一日总结，分别给一份独立画布逻辑。
//  - 风格参考 WeatherSkillRenderer：纯几何 + 文字，避免高频纹理在墨水屏抖动后糊掉。
//  - 颜色克制，主体走米色背景 + 黑色文字 + 关键色点缀，落到 6 色墨水屏上仍清晰可读。
//

import UIKit

enum HealthSkillRenderer {
    private enum Layout {
        static let canvasSize = CGSize(width: 400, height: 600)
        static let outerMargin: CGFloat = 16
    }

    private enum Palette {
        static let background = UIColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1)
        static let outline = UIColor.black
        static let divider = UIColor(white: 0.72, alpha: 1)
        static let accentSleep = UIColor(red: 0.32, green: 0.32, blue: 0.62, alpha: 1)
        static let accentFitness = UIColor(red: 0.88, green: 0.16, blue: 0.16, alpha: 1)
        static let accentDaily = UIColor(red: 0.95, green: 0.56, blue: 0.06, alpha: 1)
        static let ringEnergy = UIColor(red: 0.93, green: 0.09, blue: 0.34, alpha: 1)
        static let ringExercise = UIColor(red: 0.41, green: 0.78, blue: 0.27, alpha: 1)
        static let ringStand = UIColor(red: 0.18, green: 0.71, blue: 0.86, alpha: 1)
        static let ringTrack = UIColor(white: 0.84, alpha: 1)
        static let secondaryText = UIColor(white: 0.30, alpha: 1)
    }

    // MARK: - 对外入口

    // 渲染始终返回 400x600。targetSize 仅为兼容调用方而保留。
    static func renderDisplayImage(snapshot: HealthSnapshot, targetSize _: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: Layout.canvasSize, format: format)
        return renderer.image { context in
            let cgContext = context.cgContext
            Palette.background.setFill()
            cgContext.fill(CGRect(origin: .zero, size: Layout.canvasSize))

            switch snapshot.mode {
            case .sleep:
                drawSleep(snapshot: snapshot.sleep, updatedAt: snapshot.updatedAt, in: cgContext)
            case .fitness:
                drawFitness(snapshot: snapshot.fitness, updatedAt: snapshot.updatedAt, in: cgContext)
            case .daily:
                drawDaily(snapshot: snapshot.daily, updatedAt: snapshot.updatedAt, in: cgContext)
            }
        }
    }

    // 占位预览：没有数据时也能在 UI 卡片里展示风格。
    static func renderPlaceholder(mode: HealthDashboardMode) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: Layout.canvasSize, format: format)
        return renderer.image { context in
            let cgContext = context.cgContext
            Palette.background.setFill()
            cgContext.fill(CGRect(origin: .zero, size: Layout.canvasSize))

            drawHeader(title: mode.title, accent: accentColor(for: mode), updatedAt: Date(), in: cgContext)
            let textRect = CGRect(x: Layout.outerMargin, y: 220, width: Layout.canvasSize.width - 2 * Layout.outerMargin, height: 160)
            drawText(
                "请连接健康设备并授权读取数据。",
                font: .systemFont(ofSize: 24, weight: .semibold),
                color: Palette.outline,
                rect: textRect,
                alignment: .center
            )
            drawText(
                mode.summary,
                font: .systemFont(ofSize: 18, weight: .medium),
                color: Palette.secondaryText,
                rect: textRect.offsetBy(dx: 0, dy: 60),
                alignment: .center
            )
        }
    }

    // MARK: - 睡眠看板

    private static func drawSleep(snapshot: HealthSleepSnapshot?, updatedAt: Date, in context: CGContext) {
        drawHeader(title: "睡眠看板", accent: Palette.accentSleep, updatedAt: updatedAt, in: context)

        guard let snapshot else {
            drawEmptyState(message: "尚未读到最近一晚的睡眠数据。", in: context)
            return
        }

        // ── 顶部主指标：总在床时长 + 入睡/起床时间 ─────────────────
        let totalDuration = snapshot.inBedDuration
        let (hours, minutes) = hoursMinutes(from: totalDuration)
        drawText(
            "\(hours)",
            font: .systemFont(ofSize: 80, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: Layout.outerMargin, y: 126, width: 110, height: 88),
            alignment: .left
        )
        drawText(
            "h",
            font: .systemFont(ofSize: 22, weight: .semibold),
            color: Palette.accentSleep,
            rect: CGRect(x: Layout.outerMargin + 92, y: 168, width: 24, height: 28),
            alignment: .left
        )
        drawText(
            "\(minutes)",
            font: .systemFont(ofSize: 40, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: Layout.outerMargin + 118, y: 148, width: 64, height: 48),
            alignment: .left
        )
        drawText(
            "min",
            font: .systemFont(ofSize: 15, weight: .semibold),
            color: Palette.accentSleep,
            rect: CGRect(x: Layout.outerMargin + 118, y: 192, width: 40, height: 18),
            alignment: .left
        )
        drawText(
            "总在床时长",
            font: .systemFont(ofSize: 13, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: Layout.outerMargin, y: 220, width: 170, height: 18),
            alignment: .left
        )

        // 右上：入睡/起床（紧凑两列，整体右边距留 16px 与画布边缘对齐）
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeOriginX: CGFloat = 212
        let timeColumnWidth: CGFloat = 86
        drawText(
            "入睡",
            font: .systemFont(ofSize: 12, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: timeOriginX, y: 116, width: timeColumnWidth, height: 16),
            alignment: .left
        )
        drawText(
            timeFormatter.string(from: snapshot.bedtime),
            font: .monospacedDigitSystemFont(ofSize: 24, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: timeOriginX, y: 132, width: timeColumnWidth, height: 30),
            alignment: .left
        )
        drawText(
            "起床",
            font: .systemFont(ofSize: 12, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: timeOriginX + timeColumnWidth, y: 116, width: timeColumnWidth, height: 16),
            alignment: .left
        )
        drawText(
            timeFormatter.string(from: snapshot.wakeTime),
            font: .monospacedDigitSystemFont(ofSize: 24, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: timeOriginX + timeColumnWidth, y: 132, width: timeColumnWidth, height: 30),
            alignment: .left
        )
        let asleepMinutes = Int(snapshot.asleepDuration / 60)
        drawText(
            String(format: "实际入睡 %dh%dm", asleepMinutes / 60, asleepMinutes % 60),
            font: .systemFont(ofSize: 12, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: timeOriginX, y: 168, width: 172, height: 18),
            alignment: .left
        )

        drawDivider(y: 248, in: context)

        // ── 睡眠阶段进度条 ────────────────────────────────────────
        let stages: [(String, TimeInterval, UIColor)] = [
            ("深睡", snapshot.deepDuration, UIColor(red: 0.13, green: 0.20, blue: 0.55, alpha: 1)),
            ("REM", snapshot.remDuration, UIColor(red: 0.29, green: 0.43, blue: 0.85, alpha: 1)),
            ("核心", snapshot.coreDuration, UIColor(red: 0.46, green: 0.62, blue: 0.92, alpha: 1)),
            ("清醒", snapshot.awakeDuration, UIColor(red: 0.92, green: 0.66, blue: 0.18, alpha: 1))
        ]
        let stageSum = stages.reduce(0.0) { $0 + $1.1 }
        let denominator = max(stageSum, snapshot.asleepDuration, 1)

        let listOrigin = CGPoint(x: Layout.outerMargin, y: 268)
        let rowHeight: CGFloat = 30
        for (index, stage) in stages.enumerated() {
            let y = listOrigin.y + CGFloat(index) * rowHeight
            drawText(
                stage.0,
                font: .systemFont(ofSize: 14, weight: .semibold),
                color: Palette.outline,
                rect: CGRect(x: listOrigin.x, y: y + 2, width: 48, height: 18),
                alignment: .left
            )
            let stageMinutes = Int(stage.1 / 60)
            let stageH = stageMinutes / 60
            let stageM = stageMinutes % 60
            let durationLabel = stageH > 0 ? "\(stageH)h\(stageM)m" : "\(stageM)m"
            drawText(
                durationLabel,
                font: .monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                color: Palette.secondaryText,
                rect: CGRect(x: listOrigin.x + 50, y: y + 2, width: 56, height: 18),
                alignment: .left
            )
            let barOriginX = listOrigin.x + 112
            let barWidth: CGFloat = Layout.canvasSize.width - 2 * Layout.outerMargin - 112
            let trackRect = CGRect(x: barOriginX, y: y + 6, width: barWidth, height: 10)
            let fillFraction = CGFloat(max(0, min(1, stage.1 / denominator)))
            drawBar(track: trackRect, fillColor: stage.2, fraction: fillFraction, in: context)
        }

        // ── 生理指标：心率 / 呼吸 / 血氧 / HRV ──────────────────────
        drawDivider(y: 400, in: context)
        drawText(
            "睡眠期间生理指标",
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: Palette.secondaryText,
            rect: CGRect(x: Layout.outerMargin, y: 412, width: 220, height: 18),
            alignment: .left
        )

        // 2x2 网格放四个指标
        let vitalsOriginY: CGFloat = 438
        let cellWidth: CGFloat = (Layout.canvasSize.width - 2 * Layout.outerMargin) / 2
        let cellHeight: CGFloat = 56
        let vitalsCells: [(String, String, String)] = [
            ("平均心率", snapshot.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "—", "bpm"),
            ("最低心率", snapshot.minHeartRate.map { "\(Int($0.rounded()))" } ?? "—", "bpm"),
            ("呼吸频率", snapshot.respiratoryRate.map { String(format: "%.1f", $0) } ?? "—", "次/分"),
            ("血氧", snapshot.bloodOxygenAverage.map { String(format: "%.1f", $0) } ?? "—", "%")
        ]
        for (index, cell) in vitalsCells.enumerated() {
            let col = index % 2
            let row = index / 2
            let originX = Layout.outerMargin + CGFloat(col) * cellWidth
            let originY = vitalsOriginY + CGFloat(row) * cellHeight
            drawText(
                cell.0,
                font: .systemFont(ofSize: 12, weight: .medium),
                color: Palette.secondaryText,
                rect: CGRect(x: originX, y: originY, width: cellWidth - 8, height: 16),
                alignment: .left
            )
            drawText(
                cell.1,
                font: .monospacedDigitSystemFont(ofSize: 24, weight: .bold),
                color: Palette.outline,
                rect: CGRect(x: originX, y: originY + 16, width: cellWidth - 56, height: 28),
                alignment: .left
            )
            drawText(
                cell.2,
                font: .systemFont(ofSize: 12, weight: .semibold),
                color: Palette.secondaryText,
                rect: CGRect(x: originX + cellWidth - 60, y: originY + 24, width: 52, height: 18),
                alignment: .right
            )
        }

        // HRV 单独一行（如果有数据）
        if let hrv = snapshot.heartRateVariability {
            drawText(
                "心率变异性 (HRV)",
                font: .systemFont(ofSize: 12, weight: .medium),
                color: Palette.secondaryText,
                rect: CGRect(x: Layout.outerMargin, y: 552, width: 200, height: 16),
                alignment: .left
            )
            drawText(
                String(format: "%.0f ms", hrv),
                font: .monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
                color: Palette.outline,
                rect: CGRect(x: Layout.canvasSize.width - Layout.outerMargin - 120, y: 552, width: 120, height: 18),
                alignment: .right
            )
        } else {
            drawFootnote("数据来自健康 App", y: 556, in: context)
        }
    }

    // MARK: - 健身看板

    private static func drawFitness(snapshot: HealthFitnessSnapshot?, updatedAt: Date, in context: CGContext) {
        drawHeader(title: "健身看板", accent: Palette.accentFitness, updatedAt: updatedAt, in: context)

        guard let snapshot else {
            drawEmptyState(message: "今日还没有可用的健身数据。", in: context)
            return
        }

        // ── 上半区：左 = 活动三环；右 = 三个环对应的核心数值 ─────────
        let ringCenter = CGPoint(x: 108, y: 246)
        let ringRadii: [CGFloat] = [78, 60, 42]
        let ringColors = [Palette.ringEnergy, Palette.ringExercise, Palette.ringStand]
        let energyGoal = snapshot.activeEnergyGoalKcal ?? 400
        let exerciseGoal = snapshot.exerciseGoalMinutes ?? 30
        let standGoal = snapshot.standGoalHours ?? 12
        let ringValues: [Double] = [
            fraction(of: snapshot.activeEnergyKcal, goal: energyGoal),
            fraction(of: snapshot.exerciseMinutes, goal: exerciseGoal),
            fraction(of: snapshot.standHours, goal: standGoal)
        ]
        for index in 0..<3 {
            drawRing(
                center: ringCenter,
                radius: ringRadii[index],
                thickness: 12,
                trackColor: Palette.ringTrack,
                fillColor: ringColors[index],
                fraction: CGFloat(ringValues[index]),
                in: context
            )
        }
        drawText(
            "活动",
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: Palette.secondaryText,
            rect: CGRect(x: 38, y: 332, width: 140, height: 18),
            alignment: .center
        )

        // 右侧三行：与活动三环颜色对应
        let metricsX: CGFloat = 208
        let metricsRows: [(UIColor, String, String, String)] = [
            (Palette.ringEnergy, "活动能量", "\(Int(snapshot.activeEnergyKcal.rounded()))", "/\(Int(energyGoal)) 千卡"),
            (Palette.ringExercise, "运动时间", "\(Int(snapshot.exerciseMinutes.rounded()))", "/\(Int(exerciseGoal)) 分钟"),
            (Palette.ringStand, "站立小时", String(format: "%.0f", snapshot.standHours), "/\(Int(standGoal)) 小时")
        ]
        for (index, row) in metricsRows.enumerated() {
            let y = 142 + CGFloat(index) * 70
            // 色点
            row.0.setFill()
            context.fillEllipse(in: CGRect(x: metricsX, y: y + 12, width: 10, height: 10))
            drawText(
                row.1,
                font: .systemFont(ofSize: 12, weight: .medium),
                color: Palette.secondaryText,
                rect: CGRect(x: metricsX + 18, y: y, width: 160, height: 16),
                alignment: .left
            )
            drawText(
                row.2,
                font: .monospacedDigitSystemFont(ofSize: 32, weight: .bold),
                color: Palette.outline,
                rect: CGRect(x: metricsX + 18, y: y + 14, width: 120, height: 40),
                alignment: .left
            )
            drawText(
                row.3,
                font: .systemFont(ofSize: 12, weight: .medium),
                color: Palette.secondaryText,
                rect: CGRect(x: metricsX + 18, y: y + 50, width: 160, height: 16),
                alignment: .left
            )
        }

        // ── 下半区：步数 / 距离 / 训练 ──────────────────────────────
        drawDivider(y: 388, in: context)
        drawText(
            "今日运动",
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: Palette.secondaryText,
            rect: CGRect(x: Layout.outerMargin, y: 402, width: 200, height: 18),
            alignment: .left
        )

        // 2x2 网格，明确尺寸，避免与底部 footnote 重叠。
        let gridOriginY: CGFloat = 430
        let cellWidth: CGFloat = (Layout.canvasSize.width - 2 * Layout.outerMargin) / 2
        let cellHeight: CGFloat = 70
        let stepsKm = snapshot.distanceMeters / 1000.0
        let workoutMinutes = Int(snapshot.workoutDuration / 60)
        let gridEntries: [(String, String, String)] = [
            ("步数", "\(snapshot.stepCount)", "步"),
            ("距离", String(format: "%.2f", stepsKm), "km"),
            ("训练次数", "\(snapshot.workoutCount)", "次"),
            ("训练时长", workoutMinutes == 0 ? "—" : "\(workoutMinutes)", "分钟")
        ]
        for (index, entry) in gridEntries.enumerated() {
            let col = index % 2
            let row = index / 2
            let originX = Layout.outerMargin + CGFloat(col) * cellWidth
            let originY = gridOriginY + CGFloat(row) * cellHeight
            drawText(
                entry.0,
                font: .systemFont(ofSize: 12, weight: .medium),
                color: Palette.secondaryText,
                rect: CGRect(x: originX, y: originY, width: cellWidth - 8, height: 16),
                alignment: .left
            )
            drawText(
                entry.1,
                font: .monospacedDigitSystemFont(ofSize: 28, weight: .bold),
                color: Palette.outline,
                rect: CGRect(x: originX, y: originY + 16, width: cellWidth - 56, height: 34),
                alignment: .left
            )
            drawText(
                entry.2,
                font: .systemFont(ofSize: 12, weight: .semibold),
                color: Palette.secondaryText,
                rect: CGRect(x: originX + cellWidth - 60, y: originY + 28, width: 52, height: 18),
                alignment: .right
            )
        }

        // 取消 footnote，避免 2x2 网格底部和注脚视觉冲突。
    }

    // MARK: - 一日总结看板

    // 简化版：一日总结只展示最关键的“今日活动 + 心率 + 昨晚睡眠”，
    // 不再罗列健身看板和睡眠看板里的所有指标，避免重复。
    private static func drawDaily(snapshot: HealthDailySnapshot?, updatedAt: Date, in context: CGContext) {
        drawHeader(title: "一日总结", accent: Palette.accentDaily, updatedAt: updatedAt, in: context)

        guard let snapshot else {
            drawEmptyState(message: "今天的数据还在记录中。", in: context)
            return
        }

        // ── 顶部：日期 + 心率（静息）─────────────────────────────
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "M月d日"
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "zh_CN")
        weekdayFormatter.dateFormat = "EEEE"
        drawText(
            monthFormatter.string(from: snapshot.date),
            font: .systemFont(ofSize: 30, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: Layout.outerMargin, y: 124, width: 220, height: 36),
            alignment: .left
        )
        drawText(
            weekdayFormatter.string(from: snapshot.date),
            font: .systemFont(ofSize: 16, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: Layout.outerMargin, y: 162, width: 220, height: 22),
            alignment: .left
        )

        // 右上：静息心率
        let restingLabel = snapshot.restingHeartRate.map { "\(Int($0.rounded()))" } ?? "—"
        drawText(
            "静息心率",
            font: .systemFont(ofSize: 12, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: 240, y: 128, width: 146, height: 16),
            alignment: .right
        )
        drawText(
            restingLabel,
            font: .monospacedDigitSystemFont(ofSize: 30, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: 240, y: 146, width: 110, height: 38),
            alignment: .right
        )
        drawText(
            "bpm",
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: Palette.accentDaily,
            rect: CGRect(x: 354, y: 158, width: 32, height: 20),
            alignment: .left
        )

        drawDivider(y: 200, in: context)

        // ── 中段：今日活动（三环 + 三个数字）────────────────────
        drawText(
            "今日活动",
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: Palette.secondaryText,
            rect: CGRect(x: Layout.outerMargin, y: 212, width: 200, height: 18),
            alignment: .left
        )

        let ringCenter = CGPoint(x: 96, y: 308)
        let ringRadii: [CGFloat] = [60, 46, 32]
        let ringColors = [Palette.ringEnergy, Palette.ringExercise, Palette.ringStand]
        let energyGoal = snapshot.fitness.activeEnergyGoalKcal ?? 400
        let exerciseGoal = snapshot.fitness.exerciseGoalMinutes ?? 30
        let standGoal = snapshot.fitness.standGoalHours ?? 12
        let fractions: [Double] = [
            fraction(of: snapshot.fitness.activeEnergyKcal, goal: energyGoal),
            fraction(of: snapshot.fitness.exerciseMinutes, goal: exerciseGoal),
            fraction(of: snapshot.fitness.standHours, goal: standGoal)
        ]
        for i in 0..<3 {
            drawRing(
                center: ringCenter,
                radius: ringRadii[i],
                thickness: 10,
                trackColor: Palette.ringTrack,
                fillColor: ringColors[i],
                fraction: CGFloat(fractions[i]),
                in: context
            )
        }

        // 右侧三个核心数字 + 右对齐的中文单位（往左收一格留出右边距）
        let metricsX: CGFloat = 188
        let activityRows: [(UIColor, String, String)] = [
            (Palette.ringEnergy, "\(Int(snapshot.fitness.activeEnergyKcal.rounded()))", "千卡"),
            (Palette.ringExercise, "\(Int(snapshot.fitness.exerciseMinutes.rounded()))", "运动分钟"),
            (Palette.ringStand, String(format: "%.0f", snapshot.fitness.standHours), "站立小时")
        ]
        for (index, row) in activityRows.enumerated() {
            let y = 230 + CGFloat(index) * 48
            row.0.setFill()
            context.fillEllipse(in: CGRect(x: metricsX, y: y + 14, width: 10, height: 10))
            drawText(
                row.1,
                font: .monospacedDigitSystemFont(ofSize: 28, weight: .bold),
                color: Palette.outline,
                rect: CGRect(x: metricsX + 18, y: y, width: 86, height: 38),
                alignment: .left
            )
            // 中文单位改为右对齐，紧贴卡片右侧但保留 16px 边距，避免视觉上溢出。
            drawText(
                row.2,
                font: .systemFont(ofSize: 12, weight: .medium),
                color: Palette.secondaryText,
                rect: CGRect(x: metricsX + 108, y: y + 14, width: Layout.canvasSize.width - Layout.outerMargin - metricsX - 108, height: 18),
                alignment: .right
            )
        }

        // 步数（贴在三环正下方做个 chip）
        drawText(
            String(format: "步数 %d · %.2f km", snapshot.fitness.stepCount, snapshot.fitness.distanceMeters / 1000.0),
            font: .systemFont(ofSize: 12, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: 28, y: 384, width: 160, height: 18),
            alignment: .center
        )

        drawDivider(y: 416, in: context)

        // ── 底部：昨晚睡眠（一行最关键的信息）─────────────────────
        drawText(
            "昨晚睡眠",
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: Palette.secondaryText,
            rect: CGRect(x: Layout.outerMargin, y: 428, width: 200, height: 18),
            alignment: .left
        )

        if let sleep = snapshot.sleep {
            let totalMinutes = Int(sleep.inBedDuration / 60)
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            drawText(
                "\(h)",
                font: .systemFont(ofSize: 56, weight: .bold),
                color: Palette.outline,
                rect: CGRect(x: Layout.outerMargin, y: 452, width: 70, height: 64),
                alignment: .left
            )
            drawText(
                "h",
                font: .systemFont(ofSize: 18, weight: .semibold),
                color: Palette.accentSleep,
                rect: CGRect(x: Layout.outerMargin + 56, y: 482, width: 20, height: 24),
                alignment: .left
            )
            drawText(
                "\(m)",
                font: .systemFont(ofSize: 32, weight: .bold),
                color: Palette.outline,
                rect: CGRect(x: Layout.outerMargin + 80, y: 466, width: 48, height: 40),
                alignment: .left
            )
            drawText(
                "min",
                font: .systemFont(ofSize: 14, weight: .semibold),
                color: Palette.accentSleep,
                rect: CGRect(x: Layout.outerMargin + 80, y: 502, width: 32, height: 18),
                alignment: .left
            )

            // 右半边：心率 + 呼吸 + 血氧 紧凑展示（一日总结里的睡眠生理摘要）
            let sleepInfoX: CGFloat = 198
            let avgHRLabel = sleep.averageHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "—"
            let respLabel = sleep.respiratoryRate.map { String(format: "%.1f 次/分", $0) } ?? "—"
            let spo2Label = sleep.bloodOxygenAverage.map { String(format: "%.1f%%", $0) } ?? "—"
            let infoRows: [(String, String)] = [
                ("平均心率", avgHRLabel),
                ("呼吸频率", respLabel),
                ("血氧", spo2Label)
            ]
            for (index, row) in infoRows.enumerated() {
                let y = 452 + CGFloat(index) * 26
                drawText(
                    row.0,
                    font: .systemFont(ofSize: 12, weight: .medium),
                    color: Palette.secondaryText,
                    rect: CGRect(x: sleepInfoX, y: y, width: 90, height: 18),
                    alignment: .left
                )
                drawText(
                    row.1,
                    font: .monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
                    color: Palette.outline,
                    rect: CGRect(x: sleepInfoX + 90, y: y, width: 110, height: 18),
                    alignment: .right
                )
            }
        } else {
            drawText(
                "暂未读到睡眠记录",
                font: .systemFont(ofSize: 14, weight: .medium),
                color: Palette.secondaryText,
                rect: CGRect(x: Layout.outerMargin, y: 462, width: 360, height: 22),
                alignment: .left
            )
        }
    }

    // MARK: - 通用绘制

    private static func drawHeader(title: String, accent: UIColor, updatedAt: Date, in context: CGContext) {
        // 不画顶部色条，也不画 accent 强调线——避免在墨水屏抖动后出现锯齿。
        _ = accent
        // 主标题
        drawText(
            title,
            font: .systemFont(ofSize: 34, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: Layout.outerMargin, y: 18, width: 240, height: 48),
            alignment: .left
        )

        // 副标题
        drawText(
            "Tatoo 健康看板",
            font: .systemFont(ofSize: 13, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: Layout.outerMargin, y: 68, width: 240, height: 18),
            alignment: .left
        )

        // 右侧更新时间
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M月d日"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        drawText(
            dateFormatter.string(from: updatedAt),
            font: .systemFont(ofSize: 17, weight: .semibold),
            color: Palette.outline,
            rect: CGRect(x: 240, y: 22, width: 144, height: 24),
            alignment: .right
        )
        drawText(
            "更新 " + timeFormatter.string(from: updatedAt),
            font: .systemFont(ofSize: 12, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: 240, y: 50, width: 144, height: 18),
            alignment: .right
        )
        // 头部底分隔线
        drawLine(
            from: CGPoint(x: Layout.outerMargin, y: 96),
            to: CGPoint(x: Layout.canvasSize.width - Layout.outerMargin, y: 96),
            color: Palette.divider,
            width: 1,
            in: context
        )
    }

    private static func drawEmptyState(message: String, in context: CGContext) {
        drawText(
            "暂无数据",
            font: .systemFont(ofSize: 30, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: 0, y: 240, width: Layout.canvasSize.width, height: 40),
            alignment: .center
        )
        drawText(
            message,
            font: .systemFont(ofSize: 16, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: 24, y: 286, width: Layout.canvasSize.width - 48, height: 60),
            alignment: .center
        )
        drawText(
            "请确认已在健康 App 内授权读取，并戴上设备记录一段时间。",
            font: .systemFont(ofSize: 13, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: 24, y: 360, width: Layout.canvasSize.width - 48, height: 40),
            alignment: .center
        )
    }

    private static func drawMetricBlock(
        primary: String,
        primaryUnit: String,
        secondary: String,
        secondaryUnit: String,
        caption: String,
        origin: CGPoint,
        in context: CGContext,
        accent: UIColor
    ) {
        // 主数字
        drawText(
            primary,
            font: .systemFont(ofSize: 78, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: origin.x, y: origin.y, width: 110, height: 84),
            alignment: .left
        )
        drawText(
            primaryUnit,
            font: .systemFont(ofSize: 22, weight: .semibold),
            color: accent,
            rect: CGRect(x: origin.x + 110, y: origin.y + 36, width: 28, height: 30),
            alignment: .left
        )
        // 次数字
        drawText(
            secondary,
            font: .systemFont(ofSize: 36, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: origin.x + 140, y: origin.y + 22, width: 64, height: 44),
            alignment: .left
        )
        drawText(
            secondaryUnit,
            font: .systemFont(ofSize: 14, weight: .semibold),
            color: accent,
            rect: CGRect(x: origin.x + 140, y: origin.y + 62, width: 64, height: 18),
            alignment: .left
        )
        // 标题说明
        drawText(
            caption,
            font: .systemFont(ofSize: 14, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: origin.x, y: origin.y + 96, width: 220, height: 18),
            alignment: .left
        )
    }

    private static func drawMetricLine(
        value: String,
        unit: String,
        caption: String,
        origin: CGPoint,
        accent: UIColor,
        in context: CGContext
    ) {
        // 圆点
        accent.setFill()
        context.fillEllipse(in: CGRect(x: origin.x, y: origin.y + 16, width: 12, height: 12))
        // 主值
        drawText(
            value,
            font: .monospacedDigitSystemFont(ofSize: 34, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: origin.x + 20, y: origin.y, width: 110, height: 42),
            alignment: .left
        )
        // 单位
        drawText(
            unit,
            font: .systemFont(ofSize: 14, weight: .semibold),
            color: Palette.secondaryText,
            rect: CGRect(x: origin.x + 20, y: origin.y + 38, width: 80, height: 18),
            alignment: .left
        )
        // 标题
        drawText(
            caption,
            font: .systemFont(ofSize: 13, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: origin.x + 110, y: origin.y + 8, width: 60, height: 18),
            alignment: .right
        )
    }

    // 通用两列指标行。
    private static func drawStatRow(
        entries: [(title: String, value: String, unit: String)],
        y: CGFloat,
        in context: CGContext
    ) {
        let columnWidth: CGFloat = (Layout.canvasSize.width - 2 * Layout.outerMargin) / CGFloat(max(entries.count, 1))
        for (index, entry) in entries.enumerated() {
            let x = Layout.outerMargin + CGFloat(index) * columnWidth
            drawText(
                entry.title,
                font: .systemFont(ofSize: 13, weight: .medium),
                color: Palette.secondaryText,
                rect: CGRect(x: x, y: y, width: columnWidth - 8, height: 18),
                alignment: .left
            )
            drawText(
                entry.value,
                font: .monospacedDigitSystemFont(ofSize: 36, weight: .bold),
                color: Palette.outline,
                rect: CGRect(x: x, y: y + 18, width: columnWidth - 8, height: 44),
                alignment: .left
            )
            drawText(
                entry.unit,
                font: .systemFont(ofSize: 13, weight: .semibold),
                color: Palette.secondaryText,
                rect: CGRect(x: x, y: y + 60, width: columnWidth - 8, height: 18),
                alignment: .left
            )
        }
    }

    private static func drawDailyStatBlock(
        title: String,
        value: String,
        unit: String,
        origin: CGPoint,
        in context: CGContext,
        valueFontSize: CGFloat = 32
    ) {
        drawText(
            title,
            font: .systemFont(ofSize: 13, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: origin.x, y: origin.y, width: 100, height: 18),
            alignment: .left
        )
        drawText(
            value,
            font: .monospacedDigitSystemFont(ofSize: valueFontSize, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: origin.x, y: origin.y + 18, width: 100, height: valueFontSize + 8),
            alignment: .left
        )
        if !unit.isEmpty {
            drawText(
                unit,
                font: .systemFont(ofSize: 12, weight: .semibold),
                color: Palette.secondaryText,
                rect: CGRect(x: origin.x, y: origin.y + 18 + valueFontSize + 4, width: 100, height: 16),
                alignment: .left
            )
        }
    }

    private static func drawDivider(y: CGFloat, in context: CGContext) {
        drawLine(
            from: CGPoint(x: Layout.outerMargin, y: y),
            to: CGPoint(x: Layout.canvasSize.width - Layout.outerMargin, y: y),
            color: Palette.divider,
            width: 1,
            in: context
        )
    }

    private static func drawFootnote(_ text: String, y: CGFloat, in context: CGContext) {
        drawText(
            text,
            font: .systemFont(ofSize: 12, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: 0, y: y, width: Layout.canvasSize.width, height: 18),
            alignment: .center
        )
    }

    private static func drawBar(track: CGRect, fillColor: UIColor, fraction: CGFloat, in context: CGContext) {
        let radius = track.height / 2
        let trackPath = UIBezierPath(roundedRect: track, cornerRadius: radius)
        Palette.ringTrack.setFill()
        trackPath.fill()

        let clamped = max(0, min(1, fraction))
        guard clamped > 0 else { return }
        var fillRect = track
        fillRect.size.width *= clamped
        // 最小可见宽度，避免极小值看不到。
        if fillRect.size.width < radius * 2 {
            fillRect.size.width = radius * 2
        }
        let fillPath = UIBezierPath(roundedRect: fillRect, cornerRadius: radius)
        fillColor.setFill()
        fillPath.fill()
    }

    private static func drawRing(
        center: CGPoint,
        radius: CGFloat,
        thickness: CGFloat,
        trackColor: UIColor,
        fillColor: UIColor,
        fraction: CGFloat,
        in context: CGContext
    ) {
        context.saveGState()
        context.setLineWidth(thickness)
        context.setLineCap(.round)

        // Track
        context.setStrokeColor(trackColor.cgColor)
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()

        // Fill
        let clamped = max(0, min(1, fraction))
        if clamped > 0 {
            context.setStrokeColor(fillColor.cgColor)
            let startAngle: CGFloat = -.pi / 2
            let endAngle: CGFloat = startAngle + .pi * 2 * clamped
            context.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            context.strokePath()
        }
        context.restoreGState()
    }

    private static func drawText(_ text: String, font: UIFont, color: UIColor, rect: CGRect, alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    private static func drawLine(from start: CGPoint, to end: CGPoint, color: UIColor, width: CGFloat, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - 工具

    private static func hoursMinutes(from interval: TimeInterval) -> (Int, Int) {
        let total = Int(interval)
        return (total / 3600, (total % 3600) / 60)
    }

    private static func fraction(of value: Double, goal: Double) -> Double {
        guard goal > 0 else { return 0 }
        return max(0, min(1.0, value / goal))
    }

    private static func accentColor(for mode: HealthDashboardMode) -> UIColor {
        switch mode {
        case .sleep:
            return Palette.accentSleep
        case .fitness:
            return Palette.accentFitness
        case .daily:
            return Palette.accentDaily
        }
    }
}
