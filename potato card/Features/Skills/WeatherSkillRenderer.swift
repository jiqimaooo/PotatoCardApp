import CoreText
import UIKit

enum WeatherSkillRenderer {
    // MARK: - 固定设备布局

    // 天气技能按真实 400x600 电子墨水屏渲染，不做响应式预览。
    // 下面所有 rect 都是画布上的绝对像素位置，调版式时优先改这些常量。
    private enum Layout {
        static let canvasSize = CGSize(width: 400, height: 600)

        static let outerMargin: CGFloat = 14

        // 顶部：左侧标题，右侧城市和日期信息。
        static let timeRect = CGRect(x: 14, y: 12, width: 230, height: 78)
        static let headerInfoRect = CGRect(x: 276, y: 14, width: 110, height: 72)
        static let topDividerY: CGFloat = 102

        // 主天气区：左侧天气图标，右侧温度，下方天气文字和体感温度。
        static let heroIconRect = CGRect(x: 18, y: 126, width: 155, height: 155)
        static let temperatureRect = CGRect(x: 192, y: 118, width: 142, height: 128)
        static let unitRect = CGRect(x: 336, y: 136, width: 48, height: 36)
        static let conditionRect = CGRect(x: 192, y: 250, width: 150, height: 38)
        static let feelsRect = CGRect(x: 192, y: 292, width: 178, height: 22)
        static let weatherMetricsRect = CGRect(x: 192, y: 318, width: 182, height: 18)
        static let middleDividerY: CGFloat = 342

        // 小时预报区：固定四列，不根据内容自动计算宽度。
        static let hourlyTitleRect = CGRect(x: 16, y: 354, width: 180, height: 28)
        static let hourlyFrame = CGRect(x: 16, y: 390, width: 368, height: 78)
        static let hourlyColumnWidth: CGFloat = 92

        // 底部 AQI 模块：必须保持在 0...600 内，避免墨水屏裁切。
        static let airQualityRect = CGRect(x: 14, y: 476, width: 372, height: 114)
    }

    // MARK: - 颜色

    // 调色板保持克制，最终图像还会经过设备侧墨水屏颜色处理。
    private enum Palette {
        static let background = UIColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1)
        static let blueBackground = UIColor(red: 0.18, green: 0.49, blue: 0.98, alpha: 1)
        static let outline = UIColor.black
        static let divider = UIColor(white: 0.72, alpha: 1)
        static let cloudFill = UIColor(red: 0.89, green: 0.94, blue: 0.98, alpha: 1)
        static let cloudMuted = UIColor(red: 0.92, green: 0.94, blue: 0.95, alpha: 1)
        static let sunFill = UIColor(red: 0.98, green: 0.72, blue: 0.19, alpha: 1)
        static let sunRay = UIColor(red: 0.95, green: 0.56, blue: 0.06, alpha: 1)
        static let moonFill = UIColor(red: 0.94, green: 0.86, blue: 0.51, alpha: 1)
        static let rain = UIColor(red: 0.17, green: 0.49, blue: 0.94, alpha: 1)
        static let snow = UIColor(red: 0.34, green: 0.62, blue: 0.97, alpha: 1)
        static let fog = UIColor(white: 0.62, alpha: 1)
        static let wind = UIColor(red: 0.39, green: 0.57, blue: 0.88, alpha: 1)
        static let thunder = UIColor(red: 0.97, green: 0.79, blue: 0.10, alpha: 1)
        static let aqiGreen = UIColor(red: 0.35, green: 0.58, blue: 0.21, alpha: 1)
        // AQI “良” 原本是亮黄 #F2C712，在米色背景 + 墨水屏上几乎不可见。
        // 改为深琥珀/暗金，保留“黄色警示”语义的同时大幅提高对比度，白字徽章也能读清。
        static let aqiYellow = UIColor(red: 0.62, green: 0.45, blue: 0.06, alpha: 1)
        static let aqiOrange = UIColor(red: 0.93, green: 0.48, blue: 0.10, alpha: 1)
        static let aqiRed = UIColor(red: 0.88, green: 0.16, blue: 0.16, alpha: 1)
        static let aqiPurple = UIColor(red: 0.58, green: 0.20, blue: 0.52, alpha: 1)
        static let accentOrange = UIColor(red: 0.93, green: 0.48, blue: 0.10, alpha: 1)
    }

    private struct RenderStyle {
        let background: UIColor
        let foreground: UIColor
        let divider: UIColor
        let cloudFill: UIColor
        let cloudMuted: UIColor
        let sunFill: UIColor
        let sunRay: UIColor
        let moonFill: UIColor
        let rain: UIColor
        let snow: UIColor
        let fog: UIColor
        let wind: UIColor
        let thunder: UIColor
        let accentText: UIColor

        private init(
            background: UIColor,
            foreground: UIColor,
            divider: UIColor,
            cloudFill: UIColor,
            cloudMuted: UIColor,
            sunFill: UIColor,
            sunRay: UIColor,
            moonFill: UIColor,
            rain: UIColor,
            snow: UIColor,
            fog: UIColor,
            wind: UIColor,
            thunder: UIColor,
            accentText: UIColor
        ) {
            self.background = background
            self.foreground = foreground
            self.divider = divider
            self.cloudFill = cloudFill
            self.cloudMuted = cloudMuted
            self.sunFill = sunFill
            self.sunRay = sunRay
            self.moonFill = moonFill
            self.rain = rain
            self.snow = snow
            self.fog = fog
            self.wind = wind
            self.thunder = thunder
            self.accentText = accentText
        }

        static let minimalist = RenderStyle(
            background: Palette.background,
            foreground: Palette.outline,
            divider: Palette.divider,
            cloudFill: Palette.cloudFill,
            cloudMuted: Palette.cloudMuted,
            sunFill: Palette.sunFill,
            sunRay: Palette.sunRay,
            moonFill: Palette.moonFill,
            rain: Palette.rain,
            snow: Palette.snow,
            fog: Palette.fog,
            wind: Palette.wind,
            thunder: Palette.thunder,
            accentText: Palette.accentOrange
        )

        // 蓝色模板只换配色，固定布局继续复用极简版。
        static let blueMinimalist = RenderStyle(
            background: Palette.blueBackground,
            foreground: UIColor.white,
            divider: UIColor.white.withAlphaComponent(0.62),
            cloudFill: UIColor.white.withAlphaComponent(0.22),
            cloudMuted: UIColor.white.withAlphaComponent(0.16),
            sunFill: UIColor.white,
            sunRay: UIColor.white.withAlphaComponent(0.78),
            moonFill: UIColor.white.withAlphaComponent(0.90),
            rain: UIColor.white,
            snow: UIColor.white,
            fog: UIColor.white.withAlphaComponent(0.76),
            wind: UIColor.white.withAlphaComponent(0.82),
            thunder: UIColor.white,
            accentText: UIColor.white
        )

        init(template: WeatherDisplayTemplate) {
            switch template {
            case .minimalist:
                self = .minimalist
            case .blueMinimalist:
                self = .blueMinimalist
            }
        }
    }

    // MARK: - 天气图标类型

    // 天气码按视觉场景分组，不为每个接口码单独画一套图标。
    // 这样能保证图标风格一致，也便于后续维护。
    private enum WeatherArtwork {
        case clearDay
        case partlyCloudyDay
        case cloudy
        case rain
        case thunderRain
        case snow
        case fog
        case wind
        case clearNight
        case partlyCloudyNight
    }

    // 渲染前使用的小时数据，已经做过时间去重和缺口补齐。
    private struct RenderHourlyItem {
        let date: Date
        let temperature: Int
        let conditionText: String
        let iconCode: String
    }

    private enum WeatherMetricIcon {
        case up
        case down
        case drop
    }

    // MARK: - 对外渲染入口

    // 保留 targetSize 参数是为了兼容现有调用方。
    // 实际渲染始终返回固定 400x600 的天气屏幕图。
    static func renderDisplayImage(
        snapshot: WeatherSkillSnapshot,
        template: WeatherDisplayTemplate,
        targetSize _: CGSize
    ) -> UIImage {
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = true

        let style = RenderStyle(template: template)
        let renderer = UIGraphicsImageRenderer(size: Layout.canvasSize, format: rendererFormat)
        return renderer.image { context in
            let bounds = CGRect(origin: .zero, size: Layout.canvasSize)
            style.background.setFill()
            context.fill(bounds)

            switch template {
            case .minimalist, .blueMinimalist:
                drawMinimalist(snapshot: snapshot, in: context.cgContext, style: style)
            }
        }
    }

    // MARK: - 屏幕分区

    // 按固定纵向结构绘制：顶部 -> 主天气 -> 四小时预报 -> AQI。
    private static func drawMinimalist(snapshot: WeatherSkillSnapshot, in context: CGContext, style: RenderStyle) {
        drawHeader(snapshot: snapshot, in: context, style: style)
        drawHero(snapshot: snapshot, in: context, style: style)
        drawHourlyRow(snapshot: snapshot, in: context, style: style)
        drawAirQuality(snapshot: snapshot, in: context, style: style)
    }

    // 顶部区域：标题和紧凑的城市日期信息。
    private static func drawHeader(snapshot: WeatherSkillSnapshot, in context: CGContext, style: RenderStyle) {
        drawText(
            "今日天气",
            font: .systemFont(ofSize: 42, weight: .bold),
            color: style.foreground,
            rect: CGRect(x: Layout.timeRect.minX, y: Layout.timeRect.minY + 20, width: 190, height: 52),
            alignment: .left
        )

        let info = Layout.headerInfoRect
        drawLocationPin(in: CGRect(x: info.minX + 2, y: info.minY + 2, width: 16, height: 20), style: style)
        drawText(
            snapshot.location.name,
            font: .systemFont(ofSize: 24, weight: .bold),
            color: style.foreground,
            rect: CGRect(x: info.minX + 22, y: info.minY, width: 88, height: 28),
            alignment: .right
        )

        drawText(
            shortDate(snapshot.updatedAt),
            font: .monospacedDigitSystemFont(ofSize: 18, weight: .medium),
            color: style.foreground,
            rect: CGRect(x: info.minX + 4, y: info.minY + 32, width: 54, height: 20),
            alignment: .left
        )
        drawText(
            weekdayText(snapshot.updatedAt),
            font: .systemFont(ofSize: 18, weight: .medium),
            color: style.foreground,
            rect: CGRect(x: info.minX + 60, y: info.minY + 32, width: 50, height: 20),
            alignment: .right
        )
        drawText(
            "更新 \(shortTime(snapshot.updatedAt))",
            font: .systemFont(ofSize: 15, weight: .medium),
            color: style.foreground,
            rect: CGRect(x: info.minX + 4, y: info.minY + 58, width: 106, height: 20),
            alignment: .left
        )

        drawLine(
            from: CGPoint(x: Layout.outerMargin, y: Layout.topDividerY),
            to: CGPoint(x: Layout.canvasSize.width - Layout.outerMargin, y: Layout.topDividerY),
            color: style.divider,
            width: 1
        )
    }

    // 主天气区域：天气图标和温度是主要视觉重心。
    private static func drawHero(snapshot: WeatherSkillSnapshot, in context: CGContext, style: RenderStyle) {
        let mainArtwork = weatherArtwork(for: snapshot.current.iconCode, fallbackText: snapshot.current.conditionText)
        if !drawQWeatherIcon(
            iconCode: snapshot.current.iconCode,
            in: Layout.heroIconRect,
            fontSize: 140,
            useFillStyle: true,
            style: style
        ) {
            drawWeatherArtwork(mainArtwork, in: Layout.heroIconRect, lineWidth: 5.5, isCompact: false, style: style)
        }

        drawText(
            "\(snapshot.current.temperature)",
            font: .systemFont(ofSize: temperatureFontSize(snapshot.current.temperature), weight: .bold),
            color: style.foreground,
            rect: Layout.temperatureRect,
            alignment: .left
        )
        drawText(
            "°C",
            font: .systemFont(ofSize: 30, weight: .bold),
            color: style.foreground,
            rect: Layout.unitRect,
            alignment: .left
        )
        drawText(
            snapshot.current.conditionText,
            font: .systemFont(ofSize: 34, weight: .bold),
            color: style.foreground,
            rect: Layout.conditionRect,
            alignment: .left
        )
        drawAttributedText(
            feelsLikeText(snapshot.current.feelsLike, style: style),
            rect: Layout.feelsRect
        )
        drawWeatherMetrics(snapshot.current, in: Layout.weatherMetricsRect, style: style)

        drawLine(
            from: CGPoint(x: Layout.outerMargin, y: Layout.middleDividerY),
            to: CGPoint(x: Layout.canvasSize.width - Layout.outerMargin, y: Layout.middleDividerY),
            color: style.divider,
            width: 1
        )
    }

    // 预报区域始终是等宽四列。绘制前会规范化时间，避免接口返回重复时间。
    private static func drawHourlyRow(snapshot: WeatherSkillSnapshot, in context: CGContext, style: RenderStyle) {
        drawText(
            "未来几小时天气",
            font: .systemFont(ofSize: 22, weight: .bold),
            color: style.foreground,
            rect: Layout.hourlyTitleRect,
            alignment: .left
        )

        let items = uniqueHourlyItems(from: snapshot)
        for (index, item) in items.enumerated() {
            let columnX = Layout.hourlyFrame.minX + CGFloat(index) * Layout.hourlyColumnWidth
            let columnRect = CGRect(
                x: columnX,
                y: Layout.hourlyFrame.minY,
                width: Layout.hourlyColumnWidth,
                height: Layout.hourlyFrame.height
            )

            if index > 0 {
                drawLine(
                    from: CGPoint(x: columnRect.minX, y: columnRect.minY + 2),
                    to: CGPoint(x: columnRect.minX, y: columnRect.maxY - 4),
                    color: style.divider,
                    width: 1
                )
            }

            drawText(
                shortTime(item.date, timeZoneID: snapshot.location.timezone),
                font: .monospacedDigitSystemFont(ofSize: 18, weight: .medium),
                color: style.foreground,
                rect: CGRect(x: columnRect.minX, y: columnRect.minY, width: columnRect.width, height: 24),
                alignment: .center
            )

            let iconRect = CGRect(x: columnRect.midX - 24, y: columnRect.minY + 24, width: 48, height: 40)
            if !drawQWeatherIcon(
                iconCode: item.iconCode,
                in: iconRect,
                fontSize: 38,
                useFillStyle: true,
                style: style
            ) {
                drawWeatherArtwork(
                    weatherArtwork(for: item.iconCode, fallbackText: item.conditionText),
                    in: iconRect,
                    lineWidth: 3,
                    isCompact: true,
                    style: style
                )
            }

            drawText(
                "\(item.temperature)°C",
                font: .systemFont(ofSize: 24, weight: .bold),
                color: style.foreground,
                rect: CGRect(x: columnRect.minX, y: columnRect.minY + 58, width: columnRect.width, height: 28),
                alignment: .center
            )
        }
    }

    // 底部 AQI 模块。左侧数字使用更高的绘制区域，避免字形和墨水屏栅格化后被裁掉。
    private static func drawAirQuality(snapshot: WeatherSkillSnapshot, in context: CGContext, style: RenderStyle) {
        let rect = Layout.airQualityRect
        let modulePath = UIBezierPath(roundedRect: rect, cornerRadius: 8)
        style.background.setFill()
        modulePath.fill()
        Palette.aqiGreen.setStroke()
        modulePath.lineWidth = 1
        modulePath.stroke()

        drawText(
            "AQI",
            font: .systemFont(ofSize: 22, weight: .bold),
            color: style.foreground,
            rect: CGRect(x: rect.minX + 14, y: rect.minY + 12, width: 78, height: 26),
            alignment: .left,
            lineHeight: 26
        )

        guard let airQuality = snapshot.airQuality else {
            drawText(
                "未开启",
                font: .systemFont(ofSize: 22, weight: .semibold),
                color: style.fog,
                rect: CGRect(x: rect.minX + 14, y: rect.minY + 54, width: 120, height: 28),
                alignment: .left
            )
            return
        }

        let valueColor = color(from: airQuality.colorHex)
        drawText(
            clampedAQIText(airQuality.aqiText),
            font: .systemFont(ofSize: 72, weight: .bold),
            color: valueColor,
            rect: CGRect(x: rect.minX + 20, y: rect.minY + 36, width: 98, height: 72),
            alignment: .left
        )

        drawLine(
            from: CGPoint(x: rect.minX + 126, y: rect.minY + 16),
            to: CGPoint(x: rect.minX + 126, y: rect.maxY - 16),
            color: style.divider,
            width: 1
        )

        let badgeRect = CGRect(x: rect.minX + 178, y: rect.minY + 10, width: 76, height: 34)
        let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 17)
        valueColor.setFill()
        badgePath.fill()
        drawText(
            airQuality.category,
            font: .systemFont(ofSize: 26, weight: .bold),
            color: .white,
            rect: badgeRect,
            alignment: .center
        )

        let barRect = CGRect(x: rect.minX + 142, y: rect.minY + 60, width: 218, height: 8)
        drawAQIBar(in: barRect)
        drawAQIPointer(value: Int(airQuality.aqiText) ?? 0, in: barRect, style: style)
        drawAQIScale(in: barRect, rightEdge: rect.maxX - 4, style: style)

        let summary = airQualitySummaryText(airQuality)
        drawText(
            summary,
            font: .systemFont(ofSize: 15, weight: .semibold),
            color: style.foreground,
            rect: CGRect(x: rect.minX + 142, y: rect.minY + 88, width: 226, height: 18),
            alignment: .left
        )
    }

    // MARK: - AQI 绘制

    // 体感下方的三项天气参数，使用固定三列避免文字把主视觉挤乱。
    private static func drawWeatherMetrics(_ current: WeatherSkillSnapshot.CurrentWeather, in rect: CGRect, style: RenderStyle) {
        let columnWidth = rect.width / 3
        let items: [(WeatherMetricIcon, String)] = [
            (.up, current.tempMax.map { "\($0)°" } ?? "--"),
            (.down, current.tempMin.map { "\($0)°" } ?? "--"),
            (.drop, current.humidity.map { "\($0)%" } ?? "--%")
        ]

        for (index, item) in items.enumerated() {
            let itemRect = CGRect(
                x: rect.minX + CGFloat(index) * columnWidth,
                y: rect.minY,
                width: columnWidth,
                height: rect.height
            )
            drawWeatherMetricIcon(item.0, in: CGRect(x: itemRect.minX, y: itemRect.minY + 2, width: 11, height: 13), style: style)
            drawText(
                item.1,
                font: .monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
                color: style.foreground,
                rect: CGRect(x: itemRect.minX + 14, y: itemRect.minY, width: itemRect.width - 14, height: itemRect.height),
                alignment: .left
            )
        }
    }

    // 五段 AQI 色带，对应设计稿里的绿、黄、橙、红、紫。
    // 具体 AQI 指针单独绘制。
    private static func drawAQIBar(in rect: CGRect) {
        let segmentColors = [
            Palette.aqiGreen,
            Palette.aqiYellow,
            Palette.aqiOrange,
            Palette.aqiRed,
            Palette.aqiPurple
        ]
        let segmentWidth = rect.width / CGFloat(segmentColors.count)
        for (index, color) in segmentColors.enumerated() {
            let segmentRect = CGRect(
                x: rect.minX + CGFloat(index) * segmentWidth,
                y: rect.minY,
                width: segmentWidth - (index == segmentColors.count - 1 ? 0 : 2),
                height: rect.height
            )
            let path = UIBezierPath(roundedRect: segmentRect, cornerRadius: rect.height / 2)
            color.setFill()
            path.fill()
        }
    }

    // 绘制 AQI 色带上方的小三角。数值会限制在 0...300，避免指针跑出模块。
    private static func drawAQIPointer(value: Int, in rect: CGRect, style: RenderStyle) {
        let clampedValue = max(0, min(300, value))
        let ratio = CGFloat(clampedValue) / 300
        let centerX = rect.minX + ratio * rect.width
        let pointer = UIBezierPath()
        pointer.move(to: CGPoint(x: centerX, y: rect.minY - 6))
        pointer.addLine(to: CGPoint(x: centerX - 6, y: rect.minY - 16))
        pointer.addLine(to: CGPoint(x: centerX + 6, y: rect.minY - 16))
        pointer.close()
        style.foreground.setFill()
        pointer.fill()
    }

    // 色带下方的刻度。字号刻意偏小，避免底部模块贴到屏幕边缘。
    private static func drawAQIScale(in rect: CGRect, rightEdge: CGFloat, style: RenderStyle) {
        let labels = ["0", "50", "100", "150", "200", "300+"]
        let positions: [CGFloat] = [0, 0.2, 0.4, 0.6, 0.8, 1.0]

        for (index, label) in labels.enumerated() {
            let centerX = rect.minX + rect.width * positions[index]
            let width: CGFloat = label == "300+" ? 36 : 26
            let labelRect: CGRect
            if index == 0 {
                labelRect = CGRect(x: rect.minX, y: rect.maxY + 2, width: width, height: 12)
            } else if index == labels.count - 1 {
                labelRect = CGRect(x: rightEdge - width, y: rect.maxY + 2, width: width, height: 12)
            } else {
                labelRect = CGRect(x: centerX - width / 2, y: rect.maxY + 2, width: width, height: 12)
            }
            drawText(
                label,
                font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                color: style.foreground,
                rect: labelRect,
                alignment: index == labels.count - 1 ? .right : .center
            )
        }
    }

    // 小参数图标用简单路径绘制，避免混入系统符号的线条风格。
    private static func drawWeatherMetricIcon(_ icon: WeatherMetricIcon, in rect: CGRect, style: RenderStyle) {
        switch icon {
        case .up:
            drawArrow(in: rect, pointsUp: true, style: style)
        case .down:
            drawArrow(in: rect, pointsUp: false, style: style)
        case .drop:
            drawWaterDrop(in: rect, style: style)
        }
    }

    private static func drawArrow(in rect: CGRect, pointsUp: Bool, style: RenderStyle) {
        let path = UIBezierPath()
        if pointsUp {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.48))
            path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.minY + rect.height * 0.48))
            path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.18, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.18, y: rect.minY + rect.height * 0.48))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.48))
        } else {
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.48))
            path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.maxY - rect.height * 0.48))
            path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.18, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.18, y: rect.maxY - rect.height * 0.48))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.48))
        }
        path.close()
        style.foreground.setFill()
        path.fill()
    }

    private static func drawWaterDrop(in rect: CGRect, style: RenderStyle) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.62),
            controlPoint1: CGPoint(x: rect.maxX - rect.width * 0.10, y: rect.minY + rect.height * 0.24),
            controlPoint2: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.42)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            controlPoint1: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.08),
            controlPoint2: CGPoint(x: rect.midX + rect.width * 0.26, y: rect.maxY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.62),
            controlPoint1: CGPoint(x: rect.midX - rect.width * 0.26, y: rect.maxY),
            controlPoint2: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            controlPoint1: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.42),
            controlPoint2: CGPoint(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.24)
        )
        path.close()
        style.rain.setFill()
        path.fill()
    }

    // MARK: - 数据规范化

    // 小时预报优先使用接口真实返回的未来小时温度；只有接口完全缺失时才用当前天气兜底。
    private static func uniqueHourlyItems(from snapshot: WeatherSkillSnapshot) -> [RenderHourlyItem] {
        let calendar = hourlyCalendar(for: snapshot.location.timezone)
        // 和风逐小时接口已经给出 fxTime/temp 的绑定关系，渲染时必须保持二者一一对应。
        let firstHour = nextWholeHour(after: Date(), calendar: calendar)
        let futureHourly = snapshot.hourly
            .filter { wholeHour(for: $0.date, calendar: calendar) >= firstHour }
            .sorted { $0.date < $1.date }

        var itemsByHour: [Date: WeatherSkillSnapshot.HourlyWeather] = [:]
        for item in futureHourly {
            let hour = wholeHour(for: item.date, calendar: calendar)
            guard hour >= firstHour, itemsByHour[hour] == nil else { continue }
            itemsByHour[hour] = item
        }

        var result = itemsByHour.keys
            .sorted()
            .prefix(4)
            .compactMap { hour -> RenderHourlyItem? in
                guard let item = itemsByHour[hour] else { return nil }
                return RenderHourlyItem(
                    date: hour,
                    temperature: item.temperature,
                    conditionText: item.conditionText,
                    iconCode: item.iconCode
                )
            }

        // 理论上 24h 接口一定足够 4 个小时；兜底只用于接口异常时保持画面完整。
        while result.count < 4 {
            let date = calendar.date(byAdding: .hour, value: result.count, to: firstHour)
                ?? firstHour.addingTimeInterval(TimeInterval(result.count * 3600))
            result.append(
                RenderHourlyItem(
                    date: date,
                    temperature: snapshot.current.temperature,
                    conditionText: snapshot.current.conditionText,
                    iconCode: snapshot.current.iconCode
                )
            )
        }

        return result
    }

    private static func nextWholeHour(after date: Date, calendar: Calendar) -> Date {
        let hourStart = wholeHour(for: date, calendar: calendar)
        if calendar.component(.minute, from: date) == 0,
           calendar.component(.second, from: date) == 0 {
            return hourStart
        }

        return calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? hourStart.addingTimeInterval(3600)
    }

    private static func wholeHour(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return calendar.date(from: components) ?? date
    }

    private static func hourlyCalendar(for timeZoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return calendar
    }

    // MARK: - 和风天气官方图标字体

    private static var didRegisterQWeatherIconFont = false

    // 使用和风图标字体时，天气码直接对应字体中的 qi-xxx 字形。
    // 字体不可用时返回 false，让调用方继续走原来的自绘图标兜底。
    @discardableResult
    private static func drawQWeatherIcon(
        iconCode: String,
        in rect: CGRect,
        fontSize: CGFloat,
        useFillStyle: Bool,
        style: RenderStyle
    ) -> Bool {
        guard
            let glyph = qWeatherIconGlyph(for: iconCode, useFillStyle: useFillStyle),
            let font = qWeatherIconFont(size: fontSize)
        else {
            return false
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: style.foreground
        ]
        let size = NSString(string: glyph).size(withAttributes: attributes)
        let drawPoint = CGPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )
        NSString(string: glyph).draw(at: drawPoint, withAttributes: attributes)
        return true
    }

    private static func qWeatherIconFont(size: CGFloat) -> UIFont? {
        registerQWeatherIconFontIfNeeded()
        return UIFont(name: "qweather-icons", size: size)
    }

    private static func registerQWeatherIconFontIfNeeded() {
        guard !didRegisterQWeatherIconFont else { return }
        didRegisterQWeatherIconFont = true

        let fontURL = Bundle.main.url(forResource: "qweather-icons", withExtension: "ttf")
            ?? Bundle.main.url(forResource: "qweather-icons", withExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.main.url(forResource: "qweather-icons", withExtension: "ttf", subdirectory: "Resources/Fonts")

        guard let fontURL else { return }
        CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
    }

    private static func qWeatherIconGlyph(for iconCode: String, useFillStyle: Bool) -> String? {
        let trimmedCode = iconCode.trimmed
        guard let code = Int(trimmedCode) else { return nil }
        let scalarValue = useFillStyle
            ? qWeatherFillScalar(for: code) ?? qWeatherOutlineScalar(for: code)
            : qWeatherOutlineScalar(for: code)
        guard
            let scalarValue,
            let scalar = UnicodeScalar(scalarValue)
        else {
            return nil
        }
        return String(Character(scalar))
    }

    private static func qWeatherOutlineScalar(for code: Int) -> Int? {
        switch code {
        case 100...104:
            return 0xF101 + code - 100
        case 150...153:
            return 0xF106 + code - 150
        case 300...318:
            return 0xF10A + code - 300
        case 350...351:
            return 0xF11D + code - 350
        case 399:
            return 0xF11F
        case 400...410:
            return 0xF120 + code - 400
        case 456...457:
            return 0xF12B + code - 456
        case 499...504:
            return 0xF12D + code - 499
        case 507...515:
            return 0xF133 + code - 507
        case 900...901:
            return 0xF144 + code - 900
        case 999:
            return 0xF146
        default:
            return nil
        }
    }

    private static func qWeatherFillScalar(for code: Int) -> Int? {
        switch code {
        case 100...104:
            return 0xF1CC + code - 100
        case 150...153:
            return 0xF1D1 + code - 150
        case 300...318:
            return 0xF1D5 + code - 300
        case 350...351:
            return 0xF1E8 + code - 350
        case 399:
            return 0xF1EA
        case 400...410:
            return 0xF1EB + code - 400
        case 456...457:
            return 0xF1F6 + code - 456
        case 499...504:
            return 0xF1F8 + code - 499
        case 507...515:
            return 0xF1FE + code - 507
        case 900...901:
            return 0xF207 + code - 900
        case 999:
            return 0xF209
        default:
            return nil
        }
    }

    // MARK: - 天气图标分发

    // 根据归类后的天气场景调用对应的自绘图标。
    private static func drawWeatherArtwork(
        _ artwork: WeatherArtwork,
        in rect: CGRect,
        lineWidth: CGFloat,
        isCompact: Bool,
        style: RenderStyle
    ) {
        switch artwork {
        case .clearDay:
            drawSun(in: rect, lineWidth: lineWidth, style: style)
        case .partlyCloudyDay:
            drawPartlyCloudy(in: rect, lineWidth: lineWidth, night: false, compact: isCompact, style: style)
        case .cloudy:
            drawCloud(in: rect, lineWidth: lineWidth, fillColor: style.cloudFill, style: style)
        case .rain:
            drawRain(in: rect, lineWidth: lineWidth, heavy: false, style: style)
        case .thunderRain:
            drawThunderRain(in: rect, lineWidth: lineWidth, style: style)
        case .snow:
            drawSnow(in: rect, lineWidth: lineWidth, style: style)
        case .fog:
            drawFog(in: rect, lineWidth: lineWidth, style: style)
        case .wind:
            drawWind(in: rect, lineWidth: lineWidth, style: style)
        case .clearNight:
            drawNightClear(in: rect, lineWidth: lineWidth, style: style)
        case .partlyCloudyNight:
            drawPartlyCloudy(in: rect, lineWidth: lineWidth, night: true, compact: isCompact, style: style)
        }
    }

    // MARK: - 天气图标基础绘制

    // 下面的图标使用 UIKit 路径绘制，不再用 SF Symbols。
    // 这样主图标和小时图标可以保持同一套视觉语言。
    private static func drawSun(in rect: CGRect, lineWidth: CGFloat, style: RenderStyle) {
        let inset = rect.width * 0.18
        let coreRect = rect.insetBy(dx: inset, dy: inset)
        let rayLength = rect.width * 0.14
        let center = CGPoint(x: rect.midX, y: rect.midY)

        for index in 0..<8 {
            let angle = CGFloat(index) * (.pi / 4)
            let start = CGPoint(
                x: center.x + cos(angle) * (coreRect.width / 2 + 6),
                y: center.y + sin(angle) * (coreRect.height / 2 + 6)
            )
            let end = CGPoint(
                x: center.x + cos(angle) * (coreRect.width / 2 + 6 + rayLength),
                y: center.y + sin(angle) * (coreRect.height / 2 + 6 + rayLength)
            )
            drawLine(from: start, to: end, color: style.sunRay, width: max(3, lineWidth * 0.75), lineCap: .round)
        }

        let circle = UIBezierPath(ovalIn: coreRect)
        style.sunFill.setFill()
        circle.fill()
    }

    // 绘制设计稿里的核心“太阳 + 云”组合，小号小时图标也复用这套形状。
    private static func drawPartlyCloudy(in rect: CGRect, lineWidth: CGFloat, night: Bool, compact: Bool, style: RenderStyle) {
        let celestialRect = CGRect(
            x: rect.minX + rect.width * 0.22,
            y: rect.minY + rect.height * 0.08,
            width: rect.width * 0.56,
            height: rect.height * 0.56
        )

        if night {
            drawMoon(in: celestialRect, lineWidth: lineWidth, style: style)
        } else {
            drawSun(in: celestialRect, lineWidth: lineWidth, style: style)
        }

        let cloudRect = CGRect(
            x: rect.minX + rect.width * 0.06,
            y: rect.minY + (compact ? rect.height * 0.34 : rect.height * 0.38),
            width: rect.width * 0.82,
            height: rect.height * 0.48
        )
        drawCloud(in: cloudRect, lineWidth: lineWidth, fillColor: style.cloudFill, style: style)
    }

    // 雨、雷、雪、雾、风都基于同一个云朵底形，保证不同天气的线条重量一致。
    private static func drawRain(in rect: CGRect, lineWidth: CGFloat, heavy: Bool, style: RenderStyle) {
        let cloudRect = CGRect(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.12, width: rect.width * 0.78, height: rect.height * 0.44)
        drawCloud(in: cloudRect, lineWidth: lineWidth, fillColor: style.cloudFill, style: style)

        let dropCount = heavy ? 4 : 3
        let startX = rect.minX + rect.width * 0.28
        for index in 0..<dropCount {
            let x = startX + CGFloat(index) * rect.width * 0.13
            let y = rect.minY + rect.height * 0.68
            drawLine(
                from: CGPoint(x: x, y: y),
                to: CGPoint(x: x - rect.width * 0.03, y: y + rect.height * 0.10),
                color: style.rain,
                width: max(3, lineWidth * 0.55),
                lineCap: .round
            )
        }
    }

    private static func drawThunderRain(in rect: CGRect, lineWidth: CGFloat, style: RenderStyle) {
        drawRain(in: rect, lineWidth: lineWidth, heavy: true, style: style)
        let bolt = UIBezierPath()
        bolt.move(to: CGPoint(x: rect.midX + 6, y: rect.minY + rect.height * 0.52))
        bolt.addLine(to: CGPoint(x: rect.midX - 6, y: rect.minY + rect.height * 0.72))
        bolt.addLine(to: CGPoint(x: rect.midX + 2, y: rect.minY + rect.height * 0.72))
        bolt.addLine(to: CGPoint(x: rect.midX - 10, y: rect.minY + rect.height * 0.90))
        bolt.addLine(to: CGPoint(x: rect.midX + 18, y: rect.minY + rect.height * 0.66))
        bolt.addLine(to: CGPoint(x: rect.midX + 8, y: rect.minY + rect.height * 0.66))
        bolt.close()
        style.thunder.setFill()
        bolt.fill()
    }

    private static func drawSnow(in rect: CGRect, lineWidth: CGFloat, style: RenderStyle) {
        let cloudRect = CGRect(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.12, width: rect.width * 0.78, height: rect.height * 0.44)
        drawCloud(in: cloudRect, lineWidth: lineWidth, fillColor: style.cloudFill, style: style)

        for index in 0..<3 {
            let center = CGPoint(
                x: rect.minX + rect.width * (0.30 + CGFloat(index) * 0.16),
                y: rect.minY + rect.height * 0.74
            )
            drawSnowflake(center: center, size: rect.width * 0.07, lineWidth: max(2.5, lineWidth * 0.42), style: style)
        }
    }

    private static func drawFog(in rect: CGRect, lineWidth: CGFloat, style: RenderStyle) {
        let cloudRect = CGRect(x: rect.minX + rect.width * 0.10, y: rect.minY + rect.height * 0.10, width: rect.width * 0.78, height: rect.height * 0.40)
        drawCloud(in: cloudRect, lineWidth: lineWidth, fillColor: style.cloudMuted, style: style)

        for row in 0..<3 {
            let y = rect.minY + rect.height * (0.62 + CGFloat(row) * 0.10)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: y))
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.82, y: y),
                controlPoint1: CGPoint(x: rect.minX + rect.width * 0.34, y: y - 4),
                controlPoint2: CGPoint(x: rect.minX + rect.width * 0.66, y: y + 4)
            )
            path.lineWidth = max(3, lineWidth * 0.52)
            path.lineCapStyle = .round
            style.fog.setStroke()
            path.stroke()
        }
    }

    private static func drawWind(in rect: CGRect, lineWidth: CGFloat, style: RenderStyle) {
        let cloudRect = CGRect(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.14, width: rect.width * 0.62, height: rect.height * 0.38)
        drawCloud(in: cloudRect, lineWidth: lineWidth, fillColor: style.cloudMuted, style: style)

        for row in 0..<2 {
            let y = rect.minY + rect.height * (0.58 + CGFloat(row) * 0.12)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.24, y: y))
            path.addCurve(
                to: CGPoint(x: rect.minX + rect.width * 0.86, y: y - 4),
                controlPoint1: CGPoint(x: rect.minX + rect.width * 0.46, y: y - 10),
                controlPoint2: CGPoint(x: rect.minX + rect.width * 0.72, y: y + 2)
            )
            path.lineWidth = max(3, lineWidth * 0.5)
            path.lineCapStyle = .round
            style.wind.setStroke()
            path.stroke()
        }
    }

    private static func drawNightClear(in rect: CGRect, lineWidth: CGFloat, style: RenderStyle) {
        drawMoon(in: CGRect(x: rect.minX + rect.width * 0.20, y: rect.minY + rect.height * 0.18, width: rect.width * 0.52, height: rect.height * 0.52), lineWidth: lineWidth, style: style)
        drawStar(center: CGPoint(x: rect.minX + rect.width * 0.70, y: rect.minY + rect.height * 0.24), size: rect.width * 0.06, style: style)
        drawStar(center: CGPoint(x: rect.minX + rect.width * 0.80, y: rect.minY + rect.height * 0.40), size: rect.width * 0.05, style: style)
    }

    private static func drawMoon(in rect: CGRect, lineWidth: CGFloat, style: RenderStyle) {
        let circle = UIBezierPath(ovalIn: rect)
        style.moonFill.setFill()
        circle.fill()

        let cutRect = rect.offsetBy(dx: rect.width * 0.26, dy: rect.height * 0.02)
        let cutPath = UIBezierPath(ovalIn: cutRect)
        style.background.setFill()
        cutPath.fill()

        let strokePath = UIBezierPath(ovalIn: rect)
        style.foreground.setStroke()
        strokePath.lineWidth = max(3, lineWidth * 0.65)
        strokePath.stroke()
    }

    private static func drawCloud(in rect: CGRect, lineWidth: CGFloat, fillColor: UIColor, style: RenderStyle) {
        let path = cloudPath(in: rect)
        fillColor.setFill()
        path.fill()
        style.foreground.setStroke()
        path.lineWidth = lineWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()
    }

    // 云朵轮廓使用 rect 内的归一化控制点。
    // 这样同一形状可以稳定缩放到主图标和小时图标尺寸。
    private static func cloudPath(in rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let minX = rect.minX
        let minY = rect.minY
        let width = rect.width
        let height = rect.height

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: minX + width * x, y: minY + height * y)
        }

        path.move(to: point(0.12, 0.84))
        path.addCurve(to: point(0.84, 0.84), controlPoint1: point(0.24, 1.02), controlPoint2: point(0.74, 1.02))
        path.addCurve(to: point(0.88, 0.58), controlPoint1: point(0.97, 0.84), controlPoint2: point(0.99, 0.67))
        path.addCurve(to: point(0.70, 0.42), controlPoint1: point(0.87, 0.48), controlPoint2: point(0.80, 0.40))
        path.addCurve(to: point(0.56, 0.20), controlPoint1: point(0.69, 0.24), controlPoint2: point(0.62, 0.16))
        path.addCurve(to: point(0.30, 0.30), controlPoint1: point(0.48, 0.06), controlPoint2: point(0.34, 0.10))
        path.addCurve(to: point(0.20, 0.48), controlPoint1: point(0.23, 0.32), controlPoint2: point(0.18, 0.40))
        path.addCurve(to: point(0.12, 0.84), controlPoint1: point(0.03, 0.50), controlPoint2: point(-0.02, 0.77))
        path.close()
        return path
    }

    private static func drawSnowflake(center: CGPoint, size: CGFloat, lineWidth: CGFloat, style: RenderStyle) {
        for angle in stride(from: 0.0, to: Double.pi, by: Double.pi / 3) {
            let dx = cos(angle) * size
            let dy = sin(angle) * size
            drawLine(
                from: CGPoint(x: center.x - dx, y: center.y - dy),
                to: CGPoint(x: center.x + dx, y: center.y + dy),
                color: style.snow,
                width: lineWidth,
                lineCap: .round
            )
        }
    }

    private static func drawStar(center: CGPoint, size: CGFloat, style: RenderStyle) {
        drawLine(
            from: CGPoint(x: center.x - size, y: center.y),
            to: CGPoint(x: center.x + size, y: center.y),
            color: style.thunder,
            width: 2,
            lineCap: .round
        )
        drawLine(
            from: CGPoint(x: center.x, y: center.y - size),
            to: CGPoint(x: center.x, y: center.y + size),
            color: style.thunder,
            width: 2,
            lineCap: .round
        )
    }

    private static func drawLocationPin(in rect: CGRect, style: RenderStyle) {
        guard let image = UIImage(
            systemName: "location.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        )?.withTintColor(style.foreground, renderingMode: .alwaysOriginal) else {
            return
        }
        image.draw(in: rect)
    }

    // MARK: - 天气码映射

    // 优先按和风天气官方 icon code 映射，再用中文天气文案兜底。
    // 未知天气默认显示阴天图标，避免出现空白。
    private static func weatherArtwork(for iconCode: String, fallbackText: String) -> WeatherArtwork {
        let trimmedText = fallbackText.trimmed

        switch iconCode {
        case "100":
            return .clearDay
        case "101", "102", "103":
            return .partlyCloudyDay
        case "104":
            return .cloudy
        case "150":
            return .clearNight
        case "151", "152", "153", "154":
            return .partlyCloudyNight
        case "200", "201", "202", "203", "204", "205", "206", "207", "208", "209", "210", "211", "212", "213":
            return .wind
        case "300", "301", "305", "306", "307", "308", "309", "310", "311", "312", "313", "314", "315", "316", "317", "318", "350", "351", "399":
            return .rain
        case "302", "303", "304":
            return .thunderRain
        case "400", "401", "402", "403", "404", "405", "406", "407", "408", "409", "410", "456", "457", "499":
            return .snow
        case "500", "501", "502", "503", "504", "507", "508", "509", "510", "511", "512", "513", "514", "515":
            return .fog
        default:
            break
        }

        if trimmedText.contains("雷") {
            return .thunderRain
        }
        if trimmedText.contains("雪") {
            return .snow
        }
        if trimmedText.contains("雨") {
            return .rain
        }
        if trimmedText.contains("雾") || trimmedText.contains("霾") {
            return .fog
        }
        if trimmedText.contains("风") {
            return .wind
        }
        if trimmedText.contains("晴") && trimmedText.contains("云") {
            return .partlyCloudyDay
        }
        if trimmedText.contains("云") || trimmedText.contains("阴") {
            return .cloudy
        }
        if trimmedText.contains("晴") {
            return .clearDay
        }
        return .cloudy
    }

    // MARK: - 绘制工具

    // 通用文字绘制方法。所有文字都有固定 rect，所以这里选择裁切而不是自动换行。
    private static func drawText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        rect: CGRect,
        alignment: NSTextAlignment,
        lineHeight: CGFloat? = nil
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byClipping
        if let lineHeight {
            paragraphStyle.minimumLineHeight = lineHeight
            paragraphStyle.maximumLineHeight = lineHeight
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        NSString(string: text).draw(in: rect.integral, withAttributes: attributes)
    }

    private static func drawAttributedText(_ attributedText: NSAttributedString, rect: CGRect) {
        attributedText.draw(in: rect.integral)
    }

    private static func drawLine(
        from start: CGPoint,
        to end: CGPoint,
        color: UIColor,
        width: CGFloat,
        lineCap: CGLineCap = .butt
    ) {
        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: end)
        path.lineWidth = width
        path.lineCapStyle = lineCap == .round ? .round : .butt
        color.setStroke()
        path.stroke()
    }

    // MARK: - 格式化

    private static func shortTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    private static func shortTime(_ date: Date, timeZoneID: String) -> String {
        guard let timeZone = TimeZone(identifier: timeZoneID) else {
            return shortTime(date)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func shortDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static func weekdayText(_ date: Date) -> String {
        weekdayFormatter.string(from: date)
    }

    private static func lunarText(_ date: Date) -> String {
        let components: DateComponents
        if #available(iOS 17.0, *) {
            components = lunarCalendar.dateComponents([.month, .day, .isLeapMonth], from: date)
        } else {
            // iOS 16 没有 isLeapMonth 组件，低版本只展示农历月日。
            components = lunarCalendar.dateComponents([.month, .day], from: date)
        }
        guard let month = components.month, let day = components.day else {
            return ""
        }

        let monthName = lunarMonthNames[max(0, min(lunarMonthNames.count - 1, month - 1))]
        let dayName = lunarDayNames[max(0, min(lunarDayNames.count - 1, day - 1))]
        let isLeapMonth: Bool
        if #available(iOS 17.0, *) {
            isLeapMonth = components.isLeapMonth == true
        } else {
            isLeapMonth = false
        }
        let prefix = isLeapMonth ? "农历闰" : "农历"
        return prefix + monthName + dayName
    }

    // 生成“体感 13°C”这种混色文字。
    private static func feelsLikeText(_ feelsLike: Int, style: RenderStyle) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byClipping

        let result = NSMutableAttributedString(
            string: "体感 ",
            attributes: [
                .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: style.foreground,
                .paragraphStyle: paragraphStyle
            ]
        )
        result.append(
            NSAttributedString(
                string: "\(feelsLike)°C",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                    .foregroundColor: style.accentText,
                    .paragraphStyle: paragraphStyle
                ]
            )
        )
        return result
    }

    // 两位数温度使用主视觉字号。负数或三位数会降档，避免和 °C 单位重叠。
    private static func temperatureFontSize(_ temperature: Int) -> CGFloat {
        let text = "\(temperature)"
        if text.count <= 2 {
            return 118
        }
        if text.count == 3 {
            return 100
        }
        return 86
    }

    // AQI 正常应该是数字。这里限制长度，保护固定宽度的左侧数字栏。
    private static func clampedAQIText(_ value: String) -> String {
        let trimmed = value.trimmed
        guard trimmed.count > 3 else { return trimmed }
        return String(trimmed.prefix(3))
    }

    // 生成 AQI 模块右下角的短说明文字。
    private static func airQualitySummaryText(_ airQuality: WeatherSkillSnapshot.AirQuality) -> String {
        if airQuality.category == "优" || airQuality.category.lowercased() == "excellent" {
            return "空气质量优，适合外出活动"
        }

        if airQuality.primaryPollutant.trimmed.isEmpty {
            return "空气质量\(airQuality.category)"
        }

        return "空气质量\(airQuality.category)，首要污染物\(airQuality.primaryPollutant)"
    }

    // AQI 颜色在 Store 中已归一化为 hex，这里转换成 UIColor。
    private static func color(from hex: String) -> UIColor {
        let trimmed = hex.replacingOccurrences(of: "#", with: "")
        guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else {
            return Palette.aqiGreen
        }

        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255

        // 和风 API 在 AQI “良” 区间返回亮黄色（如 #FFFF00 / #F5C13E），
        // 在米色背景的墨水屏上几乎看不见，这里统一映射到调色板里的深琥珀色，
        // 保证 AQI 大数字、身份徽章和底部色带的黄色档位保持一致。
        // 条件：R/G 均偏高且接近、B 偏低，排除橙色（G/R 明显偏低）。
        if red >= 0.80, blue <= 0.40, green / max(red, 0.0001) >= 0.70 {
            return Palette.aqiYellow
        }

        return UIColor(red: red, green: green, blue: blue, alpha: 1)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM/dd"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "ccc"
        return formatter
    }()

    private static let lunarCalendar: Calendar = {
        var calendar = Calendar(identifier: .chinese)
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }()

    private static let lunarMonthNames = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月"
    ]

    private static let lunarDayNames = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]
}
