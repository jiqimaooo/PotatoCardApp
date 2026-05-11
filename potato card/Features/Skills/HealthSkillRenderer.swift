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

        // 主指标：总在床时长
        let totalDuration = snapshot.inBedDuration
        let (hours, minutes) = hoursMinutes(from: totalDuration)
        drawMetricBlock(
            primary: "\(hours)",
            primaryUnit: "h",
            secondary: "\(minutes)",
            secondaryUnit: "min",
            caption: "总在床时长",
            origin: CGPoint(x: Layout.outerMargin, y: 130),
            in: context,
            accent: Palette.accentSleep
        )

        // 入睡/起床时间
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeY: CGFloat = 130
        let timeOriginX: CGFloat = 232
        drawText(
            "入睡 " + timeFormatter.string(from: snapshot.bedtime),
            font: .systemFont(ofSize: 20, weight: .semibold),
            color: Palette.outline,
            rect: CGRect(x: timeOriginX, y: timeY + 12, width: 152, height: 28),
            alignment: .left
        )
        drawText(
            "起床 " + timeFormatter.string(from: snapshot.wakeTime),
            font: .systemFont(ofSize: 20, weight: .semibold),
            color: Palette.outline,
            rect: CGRect(x: timeOriginX, y: timeY + 50, width: 152, height: 28),
            alignment: .left
        )
        drawText(
            String(format: "实际入睡 %dh%dm", Int(snapshot.asleepDuration) / 3600, (Int(snapshot.asleepDuration) % 3600) / 60),
            font: .systemFont(ofSize: 15, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: timeOriginX, y: timeY + 90, width: 156, height: 22),
            alignment: .left
        )

        drawDivider(y: 282, in: context)

        // 各阶段进度条
        let stages: [(String, TimeInterval, UIColor)] = [
            ("深睡", snapshot.deepDuration, UIColor(red: 0.13, green: 0.20, blue: 0.55, alpha: 1)),
            ("REM", snapshot.remDuration, UIColor(red: 0.29, green: 0.43, blue: 0.85, alpha: 1)),
            ("核心", snapshot.coreDuration, UIColor(red: 0.46, green: 0.62, blue: 0.92, alpha: 1)),
            ("清醒", snapshot.awakeDuration, UIColor(red: 0.92, green: 0.66, blue: 0.18, alpha: 1))
        ]

        // 总样本时间用 max(各阶段之和, asleep) 防止分母为 0。
        let stageSum = stages.reduce(0.0) { $0 + $1.1 }
        let denominator = max(stageSum, snapshot.asleepDuration, 1)

        let listOrigin = CGPoint(x: Layout.outerMargin, y: 310)
        let rowHeight: CGFloat = 38
        for (index, stage) in stages.enumerated() {
            let y = listOrigin.y + CGFloat(index) * rowHeight
            // 标签
            drawText(
                stage.0,
                font: .systemFont(ofSize: 17, weight: .semibold),
                color: Palette.outline,
                rect: CGRect(x: listOrigin.x, y: y, width: 60, height: 24),
                alignment: .left
            )
            // 时长文字
            let stageMinutes = Int(stage.1 / 60)
            let stageH = stageMinutes / 60
            let stageM = stageMinutes % 60
            let durationLabel = stageH > 0 ? "\(stageH)h\(stageM)m" : "\(stageM)m"
            drawText(
                durationLabel,
                font: .monospacedDigitSystemFont(ofSize: 15, weight: .medium),
                color: Palette.secondaryText,
                rect: CGRect(x: listOrigin.x + 64, y: y, width: 64, height: 24),
                alignment: .left
            )
            // 进度条
            let barOriginX = listOrigin.x + 134
            let barWidth: CGFloat = Layout.canvasSize.width - 2 * Layout.outerMargin - 134
            let trackRect = CGRect(x: barOriginX, y: y + 8, width: barWidth, height: 10)
            let fillFraction = CGFloat(max(0, min(1, stage.1 / denominator)))
            drawBar(track: trackRect, fillColor: stage.2, fraction: fillFraction, in: context)
        }

        // 底部注脚
        drawFootnote(
            "数据来自健康 App · 仅供参考",
            y: 560,
            in: context
        )
    }

    // MARK: - 健身看板

    private static func drawFitness(snapshot: HealthFitnessSnapshot?, updatedAt: Date, in context: CGContext) {
        drawHeader(title: "健身看板", accent: Palette.accentFitness, updatedAt: updatedAt, in: context)

        guard let snapshot else {
            drawEmptyState(message: "今日还没有可用的健身数据。", in: context)
            return
        }

        // 活动三环
        let ringCenter = CGPoint(x: 122, y: 270)
        let ringRadii: [CGFloat] = [82, 64, 46]
        let ringColors = [Palette.ringEnergy, Palette.ringExercise, Palette.ringStand]
        let ringValues: [Double] = [
            fraction(of: snapshot.activeEnergyKcal, goal: snapshot.activeEnergyGoalKcal ?? 400),
            fraction(of: snapshot.exerciseMinutes, goal: snapshot.exerciseGoalMinutes ?? 30),
            fraction(of: snapshot.standHours, goal: snapshot.standGoalHours ?? 12)
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

        // 右侧主指标
        let energyOrigin = CGPoint(x: 232, y: 156)
        drawMetricLine(
            value: "\(Int(snapshot.activeEnergyKcal.rounded()))",
            unit: "千卡",
            caption: "活动能量",
            origin: energyOrigin,
            accent: Palette.ringEnergy,
            in: context
        )
        drawMetricLine(
            value: "\(Int(snapshot.exerciseMinutes.rounded()))",
            unit: "分钟",
            caption: "运动时间",
            origin: CGPoint(x: 232, y: 222),
            accent: Palette.ringExercise,
            in: context
        )
        drawMetricLine(
            value: String(format: "%.1f", snapshot.standHours),
            unit: "小时",
            caption: "站立",
            origin: CGPoint(x: 232, y: 288),
            accent: Palette.ringStand,
            in: context
        )

        drawDivider(y: 372, in: context)

        // 步数 / 距离 / 训练
        let stepsKm = snapshot.distanceMeters / 1000.0
        drawStatRow(
            entries: [
                (title: "步数", value: "\(snapshot.stepCount)", unit: "步"),
                (title: "距离", value: String(format: "%.2f", stepsKm), unit: "km")
            ],
            y: 396,
            in: context
        )

        let workoutDurationMinutes = Int(snapshot.workoutDuration / 60)
        let workoutDurationLabel = workoutDurationMinutes == 0 ? "—" : "\(workoutDurationMinutes)"
        drawStatRow(
            entries: [
                (title: "训练次数", value: "\(snapshot.workoutCount)", unit: "次"),
                (title: "训练时长", value: workoutDurationLabel, unit: "min")
            ],
            y: 470,
            in: context
        )

        drawFootnote(
            "Apple 活动 · 数据来自健康 App",
            y: 560,
            in: context
        )
    }

    // MARK: - 一日总结看板

    private static func drawDaily(snapshot: HealthDailySnapshot?, updatedAt: Date, in context: CGContext) {
        drawHeader(title: "一日总结", accent: Palette.accentDaily, updatedAt: updatedAt, in: context)

        guard let snapshot else {
            drawEmptyState(message: "今天的数据还在记录中。", in: context)
            return
        }

        // 顶部：日期 + 概览
        let calendar = Calendar.current
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "zh_CN")
        weekdayFormatter.dateFormat = "EEEE"

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "M月d日"

        drawText(
            monthFormatter.string(from: snapshot.date),
            font: .systemFont(ofSize: 26, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: Layout.outerMargin, y: 124, width: 220, height: 32),
            alignment: .left
        )
        drawText(
            weekdayFormatter.string(from: snapshot.date),
            font: .systemFont(ofSize: 18, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: Layout.outerMargin, y: 158, width: 220, height: 24),
            alignment: .left
        )

        // 右上：心率
        let restingLabel: String
        if let resting = snapshot.restingHeartRate {
            restingLabel = "\(Int(resting.rounded()))"
        } else {
            restingLabel = "—"
        }
        let avgLabel: String
        if let avg = snapshot.avgHeartRate {
            avgLabel = "\(Int(avg.rounded()))"
        } else {
            avgLabel = "—"
        }
        drawText(
            "静息心率",
            font: .systemFont(ofSize: 13, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: 230, y: 124, width: 156, height: 16),
            alignment: .right
        )
        drawText(
            "\(restingLabel) bpm",
            font: .systemFont(ofSize: 22, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: 230, y: 142, width: 156, height: 28),
            alignment: .right
        )
        drawText(
            "今日平均 \(avgLabel) bpm",
            font: .systemFont(ofSize: 13, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: 230, y: 172, width: 156, height: 16),
            alignment: .right
        )

        drawDivider(y: 202, in: context)
        _ = calendar // 抹掉未使用警告，calendar 当前仅用于日期 formatter 构造的占位。

        // 健身环（缩小版）
        let ringCenter = CGPoint(x: 90, y: 296)
        let radii: [CGFloat] = [62, 48, 34]
        let colors = [Palette.ringEnergy, Palette.ringExercise, Palette.ringStand]
        let fractions: [Double] = [
            fraction(of: snapshot.fitness.activeEnergyKcal, goal: snapshot.fitness.activeEnergyGoalKcal ?? 400),
            fraction(of: snapshot.fitness.exerciseMinutes, goal: snapshot.fitness.exerciseGoalMinutes ?? 30),
            fraction(of: snapshot.fitness.standHours, goal: snapshot.fitness.standGoalHours ?? 12)
        ]
        for i in 0..<3 {
            drawRing(
                center: ringCenter,
                radius: radii[i],
                thickness: 12,
                trackColor: Palette.ringTrack,
                fillColor: colors[i],
                fraction: CGFloat(fractions[i]),
                in: context
            )
        }
        drawText(
            "活动",
            font: .systemFont(ofSize: 14, weight: .semibold),
            color: Palette.secondaryText,
            rect: CGRect(x: 28, y: 372, width: 124, height: 18),
            alignment: .center
        )

        // 右侧：健身核心指标
        let metricsOriginX: CGFloat = 188
        drawDailyStatBlock(
            title: "活动能量",
            value: "\(Int(snapshot.fitness.activeEnergyKcal.rounded()))",
            unit: "千卡",
            origin: CGPoint(x: metricsOriginX, y: 220),
            in: context
        )
        drawDailyStatBlock(
            title: "运动时间",
            value: "\(Int(snapshot.fitness.exerciseMinutes.rounded()))",
            unit: "分钟",
            origin: CGPoint(x: metricsOriginX + 102, y: 220),
            in: context
        )
        drawDailyStatBlock(
            title: "步数",
            value: "\(snapshot.fitness.stepCount)",
            unit: "步",
            origin: CGPoint(x: metricsOriginX, y: 292),
            in: context
        )

        let kmText = String(format: "%.2f", snapshot.fitness.distanceMeters / 1000.0)
        drawDailyStatBlock(
            title: "距离",
            value: kmText,
            unit: "km",
            origin: CGPoint(x: metricsOriginX + 102, y: 292),
            in: context
        )

        drawDivider(y: 406, in: context)

        // 底部：睡眠 + 正念
        if let sleep = snapshot.sleep {
            let totalMinutes = Int(sleep.inBedDuration / 60)
            let label = String(format: "%dh%dm", totalMinutes / 60, totalMinutes % 60)
            drawDailyStatBlock(
                title: "昨晚睡眠",
                value: label,
                unit: "",
                origin: CGPoint(x: Layout.outerMargin, y: 432),
                in: context,
                valueFontSize: 28
            )
            let asleepMinutes = Int(sleep.asleepDuration / 60)
            drawText(
                String(format: "深 %dm · REM %dm", Int(sleep.deepDuration / 60), Int(sleep.remDuration / 60)),
                font: .systemFont(ofSize: 13, weight: .medium),
                color: Palette.secondaryText,
                rect: CGRect(x: Layout.outerMargin, y: 498, width: 178, height: 18),
                alignment: .left
            )
            drawText(
                "实际入睡 \(asleepMinutes / 60)h\(asleepMinutes % 60)m",
                font: .systemFont(ofSize: 13, weight: .medium),
                color: Palette.secondaryText,
                rect: CGRect(x: Layout.outerMargin, y: 516, width: 178, height: 18),
                alignment: .left
            )
        } else {
            drawDailyStatBlock(
                title: "昨晚睡眠",
                value: "—",
                unit: "",
                origin: CGPoint(x: Layout.outerMargin, y: 432),
                in: context,
                valueFontSize: 28
            )
            drawText(
                "暂未读到睡眠记录",
                font: .systemFont(ofSize: 13, weight: .medium),
                color: Palette.secondaryText,
                rect: CGRect(x: Layout.outerMargin, y: 498, width: 178, height: 18),
                alignment: .left
            )
        }

        drawDailyStatBlock(
            title: "正念分钟",
            value: snapshot.mindfulMinutes > 0 ? "\(Int(snapshot.mindfulMinutes.rounded()))" : "—",
            unit: snapshot.mindfulMinutes > 0 ? "分钟" : "",
            origin: CGPoint(x: 220, y: 432),
            in: context,
            valueFontSize: 28
        )
        let workoutMinutes = Int(snapshot.fitness.workoutDuration / 60)
        drawText(
            "训练 \(snapshot.fitness.workoutCount) 次 · \(workoutMinutes) 分钟",
            font: .systemFont(ofSize: 13, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: 220, y: 498, width: 164, height: 18),
            alignment: .left
        )

        drawFootnote(
            "数据来自健康 App",
            y: 560,
            in: context
        )
    }

    // MARK: - 通用绘制

    private static func drawHeader(title: String, accent: UIColor, updatedAt: Date, in context: CGContext) {
        // 顶部色条
        accent.setFill()
        context.fill(CGRect(x: 0, y: 0, width: Layout.canvasSize.width, height: 6))

        // 主标题
        drawText(
            title,
            font: .systemFont(ofSize: 36, weight: .bold),
            color: Palette.outline,
            rect: CGRect(x: Layout.outerMargin, y: 28, width: 260, height: 50),
            alignment: .left
        )

        // 副标题
        drawText(
            "Tatoo 健康看板",
            font: .systemFont(ofSize: 14, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: Layout.outerMargin, y: 78, width: 260, height: 18),
            alignment: .left
        )

        // 右侧更新时间
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M月d日"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        drawText(
            dateFormatter.string(from: updatedAt),
            font: .systemFont(ofSize: 18, weight: .semibold),
            color: Palette.outline,
            rect: CGRect(x: 240, y: 32, width: 144, height: 24),
            alignment: .right
        )
        drawText(
            "更新 " + timeFormatter.string(from: updatedAt),
            font: .systemFont(ofSize: 13, weight: .medium),
            color: Palette.secondaryText,
            rect: CGRect(x: 240, y: 60, width: 144, height: 18),
            alignment: .right
        )
        // 头部底分隔线
        drawLine(
            from: CGPoint(x: Layout.outerMargin, y: 110),
            to: CGPoint(x: Layout.canvasSize.width - Layout.outerMargin, y: 110),
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
