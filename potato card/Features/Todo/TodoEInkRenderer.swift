import UIKit

enum TodoEInkRenderer {
    static func renderDisplayImage(items: [TodoItem], targetSize: CGSize) -> UIImage {
        let normalizedSize = CGSize(
            width: max(targetSize.width, 1),
            height: max(targetSize.height, 1)
        )
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = true

        let renderer = UIGraphicsImageRenderer(size: normalizedSize, format: rendererFormat)
        return renderer.image { context in
            let cgContext = context.cgContext
            UIColor.white.setFill()
            cgContext.fill(CGRect(origin: .zero, size: normalizedSize))

            let metrics = Metrics(size: normalizedSize)
            drawHeader(in: cgContext, metrics: metrics)
            drawItems(items, in: cgContext, metrics: metrics)
        }
    }

    private static func drawHeader(in context: CGContext, metrics: Metrics) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: metrics.titleFontSize, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: metrics.dateFontSize, weight: .medium),
            .foregroundColor: UIColor.darkGray
        ]

        "todos".draw(
            at: CGPoint(x: metrics.margin, y: metrics.margin),
            withAttributes: titleAttributes
        )

        dateString.draw(
            at: CGPoint(x: metrics.margin, y: metrics.margin + metrics.titleFontSize + metrics.headerGap),
            withAttributes: dateAttributes
        )

        context.setStrokeColor(UIColor.black.withAlphaComponent(0.22).cgColor)
        context.setLineWidth(max(1, metrics.size.width * 0.003))
        let lineY = metrics.contentTop - metrics.rowGap
        context.move(to: CGPoint(x: metrics.margin, y: lineY))
        context.addLine(to: CGPoint(x: metrics.size.width - metrics.margin, y: lineY))
        context.strokePath()
    }

    private static func drawItems(_ items: [TodoItem], in context: CGContext, metrics: Metrics) {
        let layout = layoutItems(items, metrics: metrics)

        if layout.visibleItems.isEmpty {
            drawEmptyState(metrics: metrics)
            return
        }

        var y = metrics.contentTop
        for entry in layout.visibleItems {
            let item = entry.item
            drawCheckbox(isDone: item.isDone, at: CGPoint(x: metrics.margin, y: y + metrics.checkboxTopInset), metrics: metrics, context: context)

            let textRect = CGRect(
                x: metrics.margin + metrics.checkboxSize + metrics.textGap,
                y: y,
                width: metrics.size.width - metrics.margin * 2 - metrics.checkboxSize - metrics.textGap,
                height: entry.rowHeight
            )
            drawTitle(item.title, isDone: item.isDone, in: textRect, metrics: metrics, context: context)

            y += entry.rowHeight + metrics.rowGap
        }

        if layout.hiddenCount > 0 {
            let remaining = "另有 \(layout.hiddenCount) 项"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: metrics.moreFontSize, weight: .medium),
                .foregroundColor: UIColor.darkGray
            ]
            remaining.draw(
                in: CGRect(x: metrics.margin, y: metrics.size.height - metrics.margin - metrics.moreFontSize - 2, width: metrics.size.width - metrics.margin * 2, height: metrics.moreFontSize + 4),
                withAttributes: attributes
            )
        }
    }

    private static func drawEmptyState(metrics: Metrics) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: metrics.bodyFontSize, weight: .medium),
            .foregroundColor: UIColor.darkGray
        ]
        "暂无待办".draw(
            in: CGRect(
                x: metrics.margin,
                y: metrics.contentTop,
                width: metrics.size.width - metrics.margin * 2,
                height: metrics.bodyFontSize * 2
            ),
            withAttributes: attributes
        )
    }

    private static func drawCheckbox(isDone: Bool, at origin: CGPoint, metrics: Metrics, context: CGContext) {
        let rect = CGRect(origin: origin, size: CGSize(width: metrics.checkboxSize, height: metrics.checkboxSize))
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(max(1.4, metrics.checkboxSize * 0.1))
        context.stroke(rect)

        guard isDone else { return }

        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(max(1.8, metrics.checkboxSize * 0.14))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.midY))
        context.addLine(to: CGPoint(x: rect.minX + rect.width * 0.43, y: rect.maxY - rect.height * 0.24))
        context.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.24))
        context.strokePath()
    }

    private static func drawTitle(_ title: String, isDone: Bool, in rect: CGRect, metrics: Metrics, context: CGContext) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.maximumLineHeight = metrics.lineHeight
        paragraph.minimumLineHeight = metrics.lineHeight

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: metrics.bodyFontSize, weight: .semibold),
            .foregroundColor: isDone ? UIColor.darkGray : UIColor.black,
            .paragraphStyle: paragraph
        ]
        title.draw(in: rect, withAttributes: attributes)

        guard isDone else { return }

        let lineY = rect.minY + min(metrics.bodyFontSize * 0.62, metrics.lineHeight * 0.5)
        context.setStrokeColor(UIColor.darkGray.cgColor)
        context.setLineWidth(max(1, metrics.bodyFontSize * 0.06))
        context.move(to: CGPoint(x: rect.minX, y: lineY))
        context.addLine(to: CGPoint(x: min(rect.maxX, rect.minX + estimatedLineWidth(for: title, metrics: metrics)), y: lineY))
        context.strokePath()
    }

    private static func layoutItems(_ items: [TodoItem], metrics: Metrics) -> (visibleItems: [(item: TodoItem, rowHeight: CGFloat)], hiddenCount: Int) {
        let availableHeight = metrics.size.height - metrics.contentTop - metrics.margin - metrics.moreFontSize
        guard availableHeight > 0 else {
            return ([], items.count)
        }

        var usedHeight: CGFloat = 0
        var visibleItems: [(item: TodoItem, rowHeight: CGFloat)] = []

        for item in items {
            let rowHeight = heightForTitle(item.title, metrics: metrics)
            let nextHeight = visibleItems.isEmpty ? rowHeight : usedHeight + metrics.rowGap + rowHeight
            if nextHeight > availableHeight, !visibleItems.isEmpty {
                break
            }

            visibleItems.append((item: item, rowHeight: rowHeight))
            usedHeight = nextHeight
        }

        return (visibleItems, max(0, items.count - visibleItems.count))
    }

    private static func heightForTitle(_ title: String, metrics: Metrics) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.maximumLineHeight = metrics.lineHeight
        paragraph.minimumLineHeight = metrics.lineHeight

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: metrics.bodyFontSize, weight: .semibold),
            .paragraphStyle: paragraph
        ]
        let textWidth = metrics.size.width - metrics.margin * 2 - metrics.checkboxSize - metrics.textGap
        let boundingRect = (title as NSString).boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let clampedHeight = min(max(metrics.minimumRowHeight, ceil(boundingRect.height)), metrics.maximumRowHeight)
        return clampedHeight
    }

    private static func estimatedLineWidth(for title: String, metrics: Metrics) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: metrics.bodyFontSize, weight: .semibold)
        ]
        return min(
            (title as NSString).size(withAttributes: attributes).width,
            metrics.size.width - metrics.margin * 2 - metrics.checkboxSize - metrics.textGap
        )
    }

    private static var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy.MM.dd EEEE"
        return formatter.string(from: Date())
    }

    private struct Metrics {
        let size: CGSize

        var margin: CGFloat {
            max(12, min(size.width, size.height) * 0.075)
        }

        var titleFontSize: CGFloat {
            max(18, min(size.width, size.height) * 0.11)
        }

        var dateFontSize: CGFloat {
            max(10, min(size.width, size.height) * 0.052)
        }

        var bodyFontSize: CGFloat {
            max(12, min(size.width, size.height) * 0.066)
        }

        var lineHeight: CGFloat {
            bodyFontSize * 1.18
        }

        var moreFontSize: CGFloat {
            max(10, min(size.width, size.height) * 0.048)
        }

        var headerGap: CGFloat {
            max(4, min(size.width, size.height) * 0.025)
        }

        var contentTop: CGFloat {
            margin + titleFontSize + headerGap + dateFontSize + rowGap * 2
        }

        var checkboxSize: CGFloat {
            max(12, bodyFontSize * 0.95)
        }

        var checkboxTopInset: CGFloat {
            max(1, bodyFontSize * 0.12)
        }

        var textGap: CGFloat {
            max(8, min(size.width, size.height) * 0.035)
        }

        var minimumRowHeight: CGFloat {
            lineHeight
        }

        var maximumRowHeight: CGFloat {
            lineHeight * 3
        }

        var rowGap: CGFloat {
            max(7, min(size.width, size.height) * 0.035)
        }
    }
}
