//
//  HealthSkillRenderer.swift
//  potato card
//
//  健康看板的 400x600 像素渲染器。
//  - 三种模式：睡眠 / 健身 / 一日总结，分别给一份独立画布逻辑。
//  - 风格参考 WeatherSkillRenderer：纯几何 + 文字，避免高频纹理在墨水屏抖动后糊掉。
//  - 全局字体比第一版整体放大，6 色墨水屏上 1m 距离也能看清。
//  - 不再画大标题/副标题，仅在右上角显示日期 + 星期 + 更新时间；
//    模式自身的内容（睡眠数字、活动环、…）已经能区分看板类型。
//

import UIKit

enum HealthSkillRenderer {
    private enum Layout {
        static let canvasSize = CGSize(width: 400, height: 600)
        static let outerMargin: CGFloat = 16
        static let contentTop: CGFloat = 92   // 顶部 header 占满 0..82，content 从 92 开始
    }

    private enum Palette {
        static let background = UIColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1)
        static let outline = UIColor.black
        // 分割线：原 0.72 在 Bayer 8x8 抖动后只剩 ~28% 黑点，1px 细线几乎被米色背景吞掉。
        // 压到 0.18 让 dither 后大部分像素落到黑色调色板上，整条线在墨水屏上清晰可辨；
        // 配合 drawDivider 把线宽提到 2px，避免 1px 子像素被抖动算法吃掉。
        static let divider = UIColor(white: 0.18, alpha: 1)
        static let accentSleep = UIColor(red: 0.32, green: 0.32, blue: 0.62, alpha: 1)
        static let accentFitness = UIColor(red: 0.88, green: 0.16, blue: 0.16, alpha: 1)
        static let accentDaily = UIColor(red: 0.95, green: 0.56, blue: 0.06, alpha: 1)
        static let ringEnergy = UIColor(red: 0.93, green: 0.09, blue: 0.34, alpha: 1)
        static let ringExercise = UIColor(red: 0.41, green: 0.78, blue: 0.27, alpha: 1)
        static let ringStand = UIColor(red: 0.18, green: 0.71, blue: 0.86, alpha: 1)
        // 三环未填充部分的底色。0.84 在 6 色墨水屏 Bayer 抖动后几乎全白，跟米色背景糊在一起完全看不出环的轮廓。
        // 压到 0.5 中灰，dither 后约一半黑像素，能清楚看到完整一圈的轨迹，又不会比填充色更黑而抢戏。
        static let ringTrack = UIColor(white: 0.5, alpha: 1)
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

            drawHeader(updatedAt: snapshot.updatedAt, in: cgContext)

            switch snapshot.mode {
            case .sleep:
                drawSleep(snapshot: snapshot.sleep, in: cgContext)
            case .fitness:
                drawFitness(snapshot: snapshot.fitness, in: cgContext)
            case .daily:
                drawDaily(snapshot: snapshot.daily, in: cgContext)
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

            drawHeader(updatedAt: Date(), in: cgContext)
            let textRect = CGRect(x: Layout.outerMargin, y: 240, width: Layout.canvasSize.width - 2 * Layout.outerMargin, height: 160)
            drawText(
                mode.title,
                font: .systemFont(ofSize: 28, weight: .bold),
                color: Palette.outline,
                rect: textRect,
                alignment: .center
            )
            drawText(
                "请连接健康设备并授权读取数据",
                font: .systemFont(ofSize: 20, weight: .medium),
                color: Palette.secondaryText,
                rect: textRect.offsetBy(dx: 0, dy: 50),
                alignment: .center
            )
        }
    }

    // MARK: - 公共顶部条

    // 顶部只在右上角放日期 + 星期 + 更新时间。
    // 整个 header 占满 y = 0..82，content 从 92 开始。
    private static func drawHeader(updatedAt: Date, in context: CGContext) {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.dateFormat = "M月d日"
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "zh_CN")
        weekdayFormatter.dateFormat = "EEEE"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        // 大日期，右上角
        drawText(
            dateFormatter.string(from: updatedAt),
            font: .systemFont(ofSize: 30, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: 200, y: 18, width: Layout.canvasSize.width - Layout.outerMargin - 200, height: 38),
            alignment: .right
        )
        // 星期 · 更新时间
        let weekday = weekdayFormatter.string(from: updatedAt)
        drawText(
            "\(weekday) · 更新 \(timeFormatter.string(from: updatedAt))",
            font: .systemFont(ofSize: 14, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: 160, y: 56, width: Layout.canvasSize.width - Layout.outerMargin - 160, height: 20),
            alignment: .right
        )
        // 底部分隔线
        drawLine(
            from: CGPoint(x: Layout.outerMargin, y: 82),
            to: CGPoint(x: Layout.canvasSize.width - Layout.outerMargin, y: 82),
            color: Palette.divider,
            width: 1,
            in: context
        )
    }

    // MARK: - 睡眠看板

    private static func drawSleep(snapshot: HealthSleepSnapshot?, in context: CGContext) {
        guard let snapshot else {
            drawEmptyState(message: "尚未读到最近一晚的睡眠数据。", in: context)
            return
        }

        // ── 顶部主指标：总时长（大字） + 入睡/起床 ─────────────
        let totalDuration = snapshot.inBedDuration
        let (hours, minutes) = hoursMinutes(from: totalDuration)
        drawText(
            "\(hours)",
            font: .systemFont(ofSize: 96, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: Layout.outerMargin, y: 100, width: 90, height: 100),
            alignment: .left
        )
        drawText(
            "h",
            font: .systemFont(ofSize: 26, weight: .semibold),
            color: Palette.accentSleep,
            rect: CGRect(x: Layout.outerMargin + 76, y: 152, width: 22, height: 30),
            alignment: .left
        )
        drawText(
            "\(minutes)",
            font: .systemFont(ofSize: 48, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: Layout.outerMargin + 102, y: 130, width: 70, height: 56),
            alignment: .left
        )
        drawText(
            "min",
            font: .systemFont(ofSize: 16, weight: .semibold),
            color: Palette.accentSleep,
            rect: CGRect(x: Layout.outerMargin + 102, y: 180, width: 44, height: 20),
            alignment: .left
        )
        drawText(
            "总在床时长",
            font: .systemFont(ofSize: 15, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: Layout.outerMargin, y: 206, width: 200, height: 20),
            alignment: .left
        )

        // 右上：入睡/起床。两列从 x=232 起，每列宽 76，整体落在 232..384 内（距右边 16px）。
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeOriginX: CGFloat = 232
        let timeColumnWidth: CGFloat = 76
        drawText(
            "入睡",
            font: .systemFont(ofSize: 15, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: timeOriginX, y: 98, width: timeColumnWidth, height: 20),
            alignment: .left
        )
        drawText(
            timeFormatter.string(from: snapshot.bedtime),
            font: .monospacedDigitSystemFont(ofSize: 22, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: timeOriginX, y: 118, width: timeColumnWidth, height: 30),
            alignment: .left
        )
        drawText(
            "起床",
            font: .systemFont(ofSize: 15, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: timeOriginX + timeColumnWidth, y: 98, width: timeColumnWidth, height: 20),
            alignment: .left
        )
        drawText(
            timeFormatter.string(from: snapshot.wakeTime),
            font: .monospacedDigitSystemFont(ofSize: 22, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: timeOriginX + timeColumnWidth, y: 118, width: timeColumnWidth, height: 30),
            alignment: .left
        )
        let asleepMinutes = Int(snapshot.asleepDuration / 60)
        drawText(
            String(format: "实际入睡 %dh%dm", asleepMinutes / 60, asleepMinutes % 60),
            font: .systemFont(ofSize: 15, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: timeOriginX, y: 152, width: timeColumnWidth * 2, height: 20),
            alignment: .left
        )

        // 睡眠评分：实际入睡下方一行。"睡眠评分" 标签 + 大数字，不再带 /99 后缀。
        drawText(
            "睡眠评分",
            font: .systemFont(ofSize: 15, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: timeOriginX, y: 184, width: timeColumnWidth, height: 22),
            alignment: .left
        )
        drawText(
            "\(snapshot.sleepScore)",
            font: .monospacedDigitSystemFont(ofSize: 32, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: timeOriginX + timeColumnWidth, y: 178, width: 72, height: 38),
            alignment: .left
        )

        drawDivider(y: 240, in: context)

        // ── 睡眠阶段进度条 ──────────────────────────────────────
        let stages: [(String, TimeInterval, UIColor)] = [
            ("深睡", snapshot.deepDuration, UIColor(red: 0.13, green: 0.20, blue: 0.55, alpha: 1)),
            ("REM", snapshot.remDuration, UIColor(red: 0.29, green: 0.43, blue: 0.85, alpha: 1)),
            ("核心", snapshot.coreDuration, UIColor(red: 0.46, green: 0.62, blue: 0.92, alpha: 1)),
            ("清醒", snapshot.awakeDuration, UIColor(red: 0.92, green: 0.66, blue: 0.18, alpha: 1))
        ]
        let stageSum = stages.reduce(0.0) { $0 + $1.1 }
        let denominator = max(stageSum, snapshot.asleepDuration, 1)

        let listOrigin = CGPoint(x: Layout.outerMargin, y: 256)
        let rowHeight: CGFloat = 34
        for (index, stage) in stages.enumerated() {
            let y = listOrigin.y + CGFloat(index) * rowHeight
            drawText(
                stage.0,
                font: .systemFont(ofSize: 16, weight: .semibold),
                color: Palette.outline,
                rect: CGRect(x: listOrigin.x, y: y + 4, width: 52, height: 20),
                alignment: .left
            )
            let stageMinutes = Int(stage.1 / 60)
            let stageH = stageMinutes / 60
            let stageM = stageMinutes % 60
            let durationLabel = stageH > 0 ? "\(stageH)h\(stageM)m" : "\(stageM)m"
            drawText(
                durationLabel,
                font: .monospacedDigitSystemFont(ofSize: 16, weight: .medium),
                color: Palette.secondaryText,
                rect: CGRect(x: listOrigin.x + 56, y: y + 4, width: 64, height: 22),
                alignment: .left
            )
            let barOriginX = listOrigin.x + 124
            let barWidth: CGFloat = Layout.canvasSize.width - Layout.outerMargin - barOriginX
            let trackRect = CGRect(x: barOriginX, y: y + 10, width: barWidth, height: 12)
            let fillFraction = CGFloat(max(0, min(1, stage.1 / denominator)))
            drawBar(track: trackRect, fillColor: stage.2, fraction: fillFraction, in: context)
        }

        drawDivider(y: 396, in: context)

        // ── 生理指标：心率 / 呼吸 / 血氧 / HRV ──────────────────
        drawText(
            "睡眠期间生理指标",
            font: .systemFont(ofSize: 15, weight: .semibold),
            color: Palette.secondaryText,
            rect: CGRect(x: Layout.outerMargin, y: 406, width: 240, height: 20),
            alignment: .left
        )

        // 2x2 网格放四个指标。采用 “标题 → 大数字（左） + 单位（跟在后面）” 的简洁版式，
        // 避免两列之间单位“飘”在中间。
        let vitalsOriginY: CGFloat = 436
        let cellWidth: CGFloat = (Layout.canvasSize.width - 2 * Layout.outerMargin) / 2
        let cellHeight: CGFloat = 62
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
                font: .systemFont(ofSize: 15, weight: .medium),
                color: Palette.secondaryText,
                rect: CGRect(x: originX, y: originY, width: cellWidth - 8, height: 20),
                alignment: .left
            )
            drawValueWithUnit(
                value: cell.1,
                unit: cell.2,
                valueFont: .monospacedDigitSystemFont(ofSize: 28, weight: .bold),
                unitFont: .systemFont(ofSize: 15, weight: .semibold),
                origin: CGPoint(x: originX, y: originY + 20),
                maxWidth: cellWidth - 8,
                valueHeight: 36
            )
        }

        // ── 底部一行三列：HRV / 近 3 天 平均 / 近 7 天 平均 ──
        // 单行布局，y=568 不会溢出 600 画布。每段都给 label + 值。整体小字统一放大到 14/16。
        let summaryY: CGFloat = 568
        // 列 1：HRV（缺数据时显示 "—"）
        let hrvLabel = snapshot.heartRateVariability.map { String(format: "%.0f ms", $0) } ?? "—"
        drawText(
            "HRV",
            font: .systemFont(ofSize: 14, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: Layout.outerMargin, y: summaryY, width: 40, height: 22),
            alignment: .left
        )
        drawText(
            hrvLabel,
            font: .monospacedDigitSystemFont(ofSize: 16, weight: .semibold),
            color: Palette.outline,
            rect: CGRect(x: Layout.outerMargin + 40, y: summaryY, width: 76, height: 22),
            alignment: .left
        )
        // 列 2：近 3 天 平均
        let recent3 = Array(snapshot.recentAsleepDurations.suffix(3))
        drawText(
            "近3天",
            font: .systemFont(ofSize: 14, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: 144, y: summaryY, width: 48, height: 22),
            alignment: .left
        )
        drawText(
            averageAsleepLabel(from: recent3),
            font: .monospacedDigitSystemFont(ofSize: 16, weight: .semibold),
            color: Palette.outline,
            rect: CGRect(x: 192, y: summaryY, width: 72, height: 22),
            alignment: .left
        )
        // 列 3：近 7 天 平均
        let recent7 = snapshot.recentAsleepDurations
        drawText(
            "近7天",
            font: .systemFont(ofSize: 14, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: 268, y: summaryY, width: 48, height: 22),
            alignment: .left
        )
        drawText(
            averageAsleepLabel(from: recent7),
            font: .monospacedDigitSystemFont(ofSize: 16, weight: .semibold),
            color: Palette.outline,
            rect: CGRect(x: 316, y: summaryY, width: Layout.canvasSize.width - Layout.outerMargin - 316, height: 22),
            alignment: .left
        )
    }

    // MARK: - 健身看板

    private static func drawFitness(snapshot: HealthFitnessSnapshot?, in context: CGContext) {
        guard let snapshot else {
            drawEmptyState(message: "今日还没有可用的健身数据。", in: context)
            return
        }

        // ── 上半区：左 = 活动三环；右 = 三个环对应的核心数值 ────
        let ringCenter = CGPoint(x: 108, y: 232)
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
                thickness: 14,
                trackColor: Palette.ringTrack,
                fillColor: ringColors[index],
                fraction: CGFloat(ringValues[index]),
                in: context
            )
        }
        drawText(
            "活动",
            font: .systemFont(ofSize: 18, weight: .heavy),
            color: Palette.outline,
            rect: CGRect(x: 38, y: 322, width: 140, height: 24),
            alignment: .center,
            strokeWidth: -2.0
        )

        // 右侧三行：与活动三环颜色对应
        let metricsX: CGFloat = 208
        let metricsRows: [(UIColor, String, String, String)] = [
            (Palette.ringEnergy, "活动能量", "\(Int(snapshot.activeEnergyKcal.rounded()))", "/\(Int(energyGoal)) 千卡"),
            (Palette.ringExercise, "运动时间", "\(Int(snapshot.exerciseMinutes.rounded()))", "/\(Int(exerciseGoal)) 分钟"),
            (Palette.ringStand, "站立小时", String(format: "%.0f", snapshot.standHours), "/\(Int(standGoal)) 小时")
        ]
        for (index, row) in metricsRows.enumerated() {
            let y: CGFloat = 124 + CGFloat(index) * 76
            // 色点
            row.0.setFill()
            context.fillEllipse(in: CGRect(x: metricsX, y: y + 14, width: 12, height: 12))
            drawText(
                row.1,
                font: .systemFont(ofSize: 16, weight: .semibold),
                color: Palette.outline,
                rect: CGRect(x: metricsX + 20, y: y, width: 160, height: 22),
                alignment: .left,
                strokeWidth: -2.0
            )
            drawText(
                row.2,
                font: .monospacedDigitSystemFont(ofSize: 38, weight: .heavy),
                color: Palette.outline,
                rect: CGRect(x: metricsX + 20, y: y + 18, width: 130, height: 46),
                alignment: .left,
                strokeWidth: -2.0
            )
            drawText(
                row.3,
                font: .systemFont(ofSize: 14, weight: .semibold),
                color: Palette.secondaryText,
                rect: CGRect(x: metricsX + 20, y: y + 58, width: 160, height: 20),
                alignment: .left
            )
        }

        // ── 下半区：今日运动 + 身体指标，两组 4 列紧凑数字 ────
        drawDivider(y: 358, in: context)

        let bottomCellWidth: CGFloat = (Layout.canvasSize.width - 2 * Layout.outerMargin) / 4
        let stepsKm = snapshot.distanceMeters / 1000.0
        let workoutMinutes = Int(snapshot.workoutDuration / 60)

        // 第 1 组：今日运动
        drawText(
            "今日运动",
            font: .systemFont(ofSize: 18, weight: .heavy),
            color: Palette.outline,
            rect: CGRect(x: Layout.outerMargin, y: 366, width: 200, height: 24),
            alignment: .left,
            strokeWidth: -2.0
        )
        let movementEntries: [(String, String, String)] = [
            ("步数", "\(snapshot.stepCount)", "步"),
            ("距离", String(format: "%.2f", stepsKm), "km"),
            ("训练次数", "\(snapshot.workoutCount)", "次"),
            ("训练时长", workoutMinutes == 0 ? "—" : "\(workoutMinutes)", "分钟")
        ]
        drawFitnessQuadRow(entries: movementEntries, originY: 394, cellWidth: bottomCellWidth)

        // 第 2 组：身体指标（心率 / 呼吸 / 血氧）。
        // 文字宽度紧凑，所以这里把数字字号压到 24，确保 "心率" 类标题始终一行。
        drawText(
            "身体指标",
            font: .systemFont(ofSize: 18, weight: .heavy),
            color: Palette.outline,
            rect: CGRect(x: Layout.outerMargin, y: 476, width: 200, height: 24),
            alignment: .left,
            strokeWidth: -2.0
        )
        let restingLabel = snapshot.restingHeartRate.map { "\(Int($0.rounded()))" } ?? "—"
        let avgHRLabel = snapshot.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "—"
        let respLabel = snapshot.respiratoryRate.map { String(format: "%.1f", $0) } ?? "—"
        let spo2Label = snapshot.bloodOxygenAverage.map { String(format: "%.1f", $0) } ?? "—"
        let vitalsEntries: [(String, String, String)] = [
            ("静息心率", restingLabel, "bpm"),
            ("平均心率", avgHRLabel, "bpm"),
            ("呼吸频率", respLabel, "次/分"),
            ("血氧", spo2Label, "%")
        ]
        drawFitnessQuadRow(entries: vitalsEntries, originY: 504, cellWidth: bottomCellWidth)
    }

    // 健身看板下半部分通用的 4 列单行：每列 = 标题 + 大数字 + 单位。
    // value 字号根据列宽折算到 24pt，确保 "7423" 也能完整显示。
    // 心率 / 呼吸 / 血氧 等标签用 .semibold + outline色，避免在墨水屏上“发灰”难辨认。
    private static func drawFitnessQuadRow(
        entries: [(String, String, String)],
        originY: CGFloat,
        cellWidth: CGFloat
    ) {
        for (index, entry) in entries.enumerated() {
            let originX = Layout.outerMargin + CGFloat(index) * cellWidth
            drawText(
                entry.0,
                font: .systemFont(ofSize: 16, weight: .semibold),
                color: Palette.outline,
                rect: CGRect(x: originX, y: originY, width: cellWidth - 4, height: 22),
                alignment: .left,
                strokeWidth: -2.0
            )
            drawText(
                entry.1,
                font: .monospacedDigitSystemFont(ofSize: 28, weight: .heavy),
                color: Palette.outline,
                rect: CGRect(x: originX, y: originY + 22, width: cellWidth - 4, height: 36),
                alignment: .left,
                strokeWidth: -2.0
            )
            drawText(
                entry.2,
                font: .systemFont(ofSize: 14, weight: .semibold),
                color: Palette.secondaryText,
                rect: CGRect(x: originX, y: originY + 56, width: cellWidth - 4, height: 20),
                alignment: .left
            )
        }
    }

    // MARK: - 一日总结看板

    // 一日总结：顶部 = 今日活动三环 + 三个数字（含 chip：步数/距离/静息心率）。
    // 中段 = 昨晚睡眠总时长 + 几个生理指标。底部 = 「今日总结」自然语言摘要 / 祝福。
    private static func drawDaily(snapshot: HealthDailySnapshot?, in context: CGContext) {
        guard let snapshot else {
            drawEmptyState(message: "今天的数据还在记录中。", in: context)
            return
        }

        // ── 今日活动 ───────────────────────────────────────────
        drawText(
            "今日活动",
            font: .systemFont(ofSize: 15, weight: .semibold),
            color: Palette.secondaryText,
            rect: CGRect(x: Layout.outerMargin, y: 94, width: 200, height: 20),
            alignment: .left
        )

        let ringCenter = CGPoint(x: 88, y: 196)
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
                thickness: 12,
                trackColor: Palette.ringTrack,
                fillColor: ringColors[i],
                fraction: CGFloat(fractions[i]),
                in: context
            )
        }

        // 右侧三个核心数字 + 中文单位（贴齐右边距）
        let metricsX: CGFloat = 184
        let activityRows: [(UIColor, String, String)] = [
            (Palette.ringEnergy, "\(Int(snapshot.fitness.activeEnergyKcal.rounded()))", "千卡"),
            (Palette.ringExercise, "\(Int(snapshot.fitness.exerciseMinutes.rounded()))", "运动分钟"),
            (Palette.ringStand, String(format: "%.0f", snapshot.fitness.standHours), "站立小时")
        ]
        for (index, row) in activityRows.enumerated() {
            let y = 130 + CGFloat(index) * 54
            row.0.setFill()
            context.fillEllipse(in: CGRect(x: metricsX, y: y + 18, width: 12, height: 12))
            drawText(
                row.1,
                font: .monospacedDigitSystemFont(ofSize: 34, weight: .bold),
                color: Palette.outline,
                rect: CGRect(x: metricsX + 20, y: y, width: 110, height: 46),
                alignment: .left
            )
            drawText(
                row.2,
                font: .systemFont(ofSize: 14, weight: .medium),
                color: Palette.secondaryText,
                rect: CGRect(x: metricsX + 130, y: y + 18, width: Layout.canvasSize.width - Layout.outerMargin - metricsX - 130, height: 20),
                alignment: .right
            )
        }

        // 三环下方 chip：步数 · 距离 · 静息心率（静息心率放这里，避免占整行）
        let stepsKm = snapshot.fitness.distanceMeters / 1000.0
        let restingPart = snapshot.restingHeartRate.map { "静息 \(Int($0.rounded())) bpm" } ?? "静息 —"
        let chipText = "步数 \(snapshot.fitness.stepCount) · \(String(format: "%.2f", stepsKm)) km · \(restingPart)"
        drawText(
            chipText,
            font: .systemFont(ofSize: 13, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: Layout.outerMargin, y: 308, width: Layout.canvasSize.width - 2 * Layout.outerMargin, height: 20),
            alignment: .center
        )

        drawDivider(y: 336, in: context)

        // ── 昨晚睡眠 ───────────────────────────────────────────
        drawText(
            "昨晚睡眠",
            font: .systemFont(ofSize: 15, weight: .semibold),
            color: Palette.secondaryText,
            rect: CGRect(x: Layout.outerMargin, y: 346, width: 200, height: 20),
            alignment: .left
        )

        if let sleep = snapshot.sleep {
            let totalMinutes = Int(sleep.inBedDuration / 60)
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            drawText(
                "\(h)",
                font: .systemFont(ofSize: 64, weight: .bold),
                color: Palette.outline,
                rect: CGRect(x: Layout.outerMargin, y: 374, width: 56, height: 70),
                alignment: .left
            )
            drawText(
                "h",
                font: .systemFont(ofSize: 20, weight: .semibold),
                color: Palette.accentSleep,
                rect: CGRect(x: Layout.outerMargin + 46, y: 410, width: 18, height: 26),
                alignment: .left
            )
            drawText(
                "\(m)",
                font: .systemFont(ofSize: 38, weight: .bold),
                color: Palette.outline,
                rect: CGRect(x: Layout.outerMargin + 66, y: 390, width: 56, height: 48),
                alignment: .left
            )
            drawText(
                "min",
                font: .systemFont(ofSize: 16, weight: .semibold),
                color: Palette.accentSleep,
                rect: CGRect(x: Layout.outerMargin + 112, y: 414, width: 40, height: 20),
                alignment: .left
            )

            // 右半边：心率 + 呼吸 + 血氧（昨晚睡眠生理摘要）。
            // 列宽：label 80 + value 96，整体落在 200..376 内（右留 16px 边距）。
            let sleepInfoX: CGFloat = 200
            let avgHRLabel = sleep.averageHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "—"
            let respLabel = sleep.respiratoryRate.map { String(format: "%.1f", $0) + " 次/分" } ?? "—"
            let spo2Label = sleep.bloodOxygenAverage.map { String(format: "%.1f%%", $0) } ?? "—"
            let infoRows: [(String, String)] = [
                ("平均心率", avgHRLabel),
                ("呼吸频率", respLabel),
                ("血氧", spo2Label)
            ]
            for (index, row) in infoRows.enumerated() {
                let y = 376 + CGFloat(index) * 26
                drawText(
                    row.0,
                    font: .systemFont(ofSize: 13, weight: .medium),
                    color: Palette.secondaryText,
                    rect: CGRect(x: sleepInfoX, y: y, width: 78, height: 20),
                    alignment: .left
                )
                drawText(
                    row.1,
                    font: .monospacedDigitSystemFont(ofSize: 15, weight: .semibold),
                    color: Palette.outline,
                    rect: CGRect(x: sleepInfoX + 78, y: y, width: Layout.canvasSize.width - Layout.outerMargin - (sleepInfoX + 78), height: 20),
                    alignment: .right
                )
            }
        } else {
            drawText(
                "暂未读到睡眠记录",
                font: .systemFont(ofSize: 16, weight: .medium),
                color: Palette.secondaryText,
                rect: CGRect(x: Layout.outerMargin, y: 396, width: 360, height: 24),
                alignment: .left
            )
        }

        drawDivider(y: 464, in: context)

        // ── 今日总结：自然语言摘要 / 祝福语 ───────────────────
        drawText(
            "今日总结",
            font: .systemFont(ofSize: 15, weight: .semibold),
            color: Palette.secondaryText,
            rect: CGRect(x: Layout.outerMargin, y: 474, width: 200, height: 20),
            alignment: .left
        )

        let summary = HealthDailySummaryWriter.compose(for: snapshot)
        // 多行文本，最多三行。整块 y=500..588。
        drawMultilineText(
            summary,
            font: .systemFont(ofSize: 15, weight: .medium),
            color: Palette.outline,
            rect: CGRect(x: Layout.outerMargin, y: 500, width: Layout.canvasSize.width - 2 * Layout.outerMargin, height: 88),
            lineHeight: 22,
            maxLines: 4
        )
    }

    // MARK: - 通用绘制

    private static func drawEmptyState(message: String, in context: CGContext) {
        drawText(
            "暂无数据",
            font: .systemFont(ofSize: 32, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: 0, y: 250, width: Layout.canvasSize.width, height: 42),
            alignment: .center
        )
        drawText(
            message,
            font: .systemFont(ofSize: 18, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: 24, y: 298, width: Layout.canvasSize.width - 48, height: 60),
            alignment: .center
        )
        drawText(
            "请确认已在健康 App 内授权读取，并戴上设备记录一段时间。",
            font: .systemFont(ofSize: 14, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: 24, y: 372, width: Layout.canvasSize.width - 48, height: 44),
            alignment: .center
        )
    }

    private static func drawDivider(y: CGFloat, in context: CGContext) {
        drawLine(
            from: CGPoint(x: Layout.outerMargin, y: y),
            to: CGPoint(x: Layout.canvasSize.width - Layout.outerMargin, y: y),
            color: Palette.divider,
            width: 2,
            in: context
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
        // 自动判断字体重量：bold 及以上加一层描边，medium/regular 只靠填充。
        // 描边原本是 -4 / -2，实际看上去太胖，压到 -2 / -0.5 后笔画仍能靠 Bayer 8x8 留住，但整体纤细一个档。
        let weight = (font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat ?? 0
        let isBold = weight >= UIFont.Weight.semibold.rawValue
        let stroke: CGFloat = isBold ? -2.0 : -0.5
        drawText(text, font: font, color: color, rect: rect, alignment: alignment, strokeWidth: stroke)
    }

    // strokeWidth 的单位是 font point 的百分比（带负号 = fill+stroke）。
    // 0 表示不加描边；非 0 时同时填充 + 描边，让字形整体加厚一圈黑色，墨水屏抖动后仍清晰。
    private static func drawText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        rect: CGRect,
        alignment: NSTextAlignment,
        strokeWidth: CGFloat
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        if strokeWidth != 0 {
            attrs[.strokeColor] = color
            attrs[.strokeWidth] = strokeWidth
        }
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    // 在一行里画 "大数字 + 紧贴的小单位"。值左对齐到 origin，
    // 单位紧跟数字的实际宽度后绘制，避免单位被右对齐推到画面中间。
    private static func drawValueWithUnit(
        value: String,
        unit: String,
        valueFont: UIFont,
        unitFont: UIFont,
        origin: CGPoint,
        maxWidth: CGFloat,
        valueHeight: CGFloat
    ) {
        let valueAttrs: [NSAttributedString.Key: Any] = [.font: valueFont]
        let valueWidth = (value as NSString).size(withAttributes: valueAttrs).width
        let clampedValueWidth = min(valueWidth, maxWidth - 32)
        drawText(
            value,
            font: valueFont,
            color: Palette.outline,
            rect: CGRect(x: origin.x, y: origin.y, width: clampedValueWidth + 2, height: valueHeight),
            alignment: .left
        )
        // 单位紧贴在数字基线附近，整体往下偏一点点。
        let unitX = origin.x + clampedValueWidth + 6
        let unitY = origin.y + valueHeight - (unitFont.lineHeight + 6)
        drawText(
            unit,
            font: unitFont,
            color: Palette.secondaryText,
            rect: CGRect(x: unitX, y: unitY, width: max(0, maxWidth - clampedValueWidth - 8), height: unitFont.lineHeight + 4),
            alignment: .left
        )
    }

    // 简单的中文换行：按 rect 宽度按字符断行（中文/英文混排都用字符级，不做精细 hyphenation）。
    private static func drawMultilineText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        rect: CGRect,
        lineHeight: CGFloat,
        maxLines: Int
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let drawRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(rect.height, CGFloat(maxLines) * lineHeight + 4))
        (text as NSString).draw(in: drawRect, withAttributes: attrs)
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

    // 只用「有记录的夜晚」计算平均，避免漏戴的夜把均值拉低；全 0 时返回 "—"。
    private static func averageAsleepLabel(from durations: [TimeInterval]) -> String {
        let nonZero = durations.filter { $0 > 0 }
        guard !nonZero.isEmpty else { return "—" }
        let avg = nonZero.reduce(0, +) / Double(nonZero.count)
        let total = Int(avg / 60)
        return "\(total / 60)h\(total % 60)m"
    }
}

// MARK: - 一日总结文案生成

// 综合「运动、睡眠、心率、体重」四个维度，挑选 2~3 句拼成总结。
// 没有可用数据时退化为温和的祝福语，避免空白。
enum HealthDailySummaryWriter {
    static func compose(for snapshot: HealthDailySnapshot) -> String {
        var lines: [String] = []

        // 活动：能量达成 / 站立 / 训练
        let energy = snapshot.fitness.activeEnergyKcal
        let energyGoal = snapshot.fitness.activeEnergyGoalKcal ?? 0
        if energy > 0, energyGoal > 0 {
            let ratio = Int((energy / energyGoal * 100).rounded())
            if ratio >= 100 {
                lines.append("活动能量已超额完成 \(ratio)%，今天动得很到位。")
            } else if ratio >= 60 {
                lines.append("活动能量已经完成 \(ratio)%，再动一会儿就闭环啦。")
            } else if ratio > 0 {
                lines.append("活动能量才完成 \(ratio)%，找时间起来走两步吧。")
            }
        } else if energy > 0 {
            lines.append("今天已经燃烧了 \(Int(energy.rounded())) 千卡。")
        }

        if snapshot.fitness.workoutCount > 0 {
            let minutes = Int(snapshot.fitness.workoutDuration / 60)
            if minutes > 0 {
                lines.append("完成了 \(snapshot.fitness.workoutCount) 次训练共 \(minutes) 分钟，辛苦啦。")
            }
        }

        if snapshot.fitness.standHours >= 9 {
            lines.append("站立 \(Int(snapshot.fitness.standHours)) 小时，作息很规律。")
        } else if snapshot.fitness.standHours > 0, snapshot.fitness.standHours < 6 {
            lines.append("今天只站了 \(Int(snapshot.fitness.standHours)) 小时，记得每小时起来动动。")
        }

        // 睡眠
        if let sleep = snapshot.sleep {
            let totalMinutes = Int(sleep.inBedDuration / 60)
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            if totalMinutes >= 7 * 60 {
                lines.append("昨晚睡了 \(h)h\(m)m，状态应该不错。")
            } else if totalMinutes > 0 {
                lines.append("昨晚只睡了 \(h)h\(m)m，今天找机会补一下。")
            }
        }

        // 心率
        if let resting = snapshot.restingHeartRate {
            let value = Int(resting.rounded())
            if value > 0 && value < 60 {
                lines.append("静息心率 \(value) bpm，心肺水平不错。")
            } else if value >= 75 {
                lines.append("静息心率 \(value) bpm 偏高，注意休息别熬夜。")
            }
        }

        // 体重趋势
        if let now = snapshot.weightKg, let last = snapshot.weightKgLastWeek {
            let diff = now - last
            let abs = Swift.abs(diff)
            if abs >= 0.2 {
                if diff < 0 {
                    lines.append(String(format: "体重比上周 −%.1fkg，坚持下去。", abs))
                } else {
                    lines.append(String(format: "体重比上周 +%.1fkg，注意一下饮食和运动。", abs))
                }
            } else {
                lines.append(String(format: "体重 %.1fkg，与上周基本持平。", now))
            }
        } else if let now = snapshot.weightKg {
            lines.append(String(format: "最新体重 %.1fkg。", now))
        }

        if lines.isEmpty {
            return blessing()
        }

        // 最多三行，按生成顺序保留前三条。
        // 之前用 shuffle()，但 SwiftUI 在同步过程中会触发多次重渲染（loadState 变化 +
        // snapshot 多次写入），每次都重洗牌 → 用户看到底部三行疯狂交换位置。
        if lines.count > 3 {
            lines = Array(lines.prefix(3))
        }
        return lines.joined(separator: "\n")
    }

    // 没有任何健康数据时也别让画面空着——丢一句轻松的祝福。
    private static func blessing() -> String {
        let pool = [
            "戴上手表记录一下，今天也要好好照顾自己呀。",
            "今天还没有读到数据，记得喝水、伸个懒腰。",
            "数据正在路上，先深呼吸三次再开始吧。",
            "暂时没有新数据，愿你今天的心情和天气一样好。"
        ]
        return pool.randomElement() ?? pool[0]
    }
}
