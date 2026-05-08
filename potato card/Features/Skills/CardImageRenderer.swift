//
//  CardImageRenderer.swift
//  potato card
//
//  把任意图片或文字渲染成土豆片尺寸的成品图。
//  - 图片走 cover 裁切，避免变形。
//  - 文字按目标画布二分搜索字号，用标点优先换行，每次随机挑一种排版。
//

import UIKit

enum CardImageRenderer {
    // MARK: - 图片：cover 裁切

    // 等比放大到刚好覆盖目标尺寸，再以中心点裁切。
    // 这里只生成展示用底图，传输前还会再过 EInkImageRenderer 做尺寸对齐和抖动。
    static func renderImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
        guard targetSize.width > 0, targetSize.height > 0 else { return image }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else { return }

            let scale = max(targetSize.width / imageSize.width, targetSize.height / imageSize.height)
            let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let drawOrigin = CGPoint(
                x: (targetSize.width - drawSize.width) / 2,
                y: (targetSize.height - drawSize.height) / 2
            )
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
    }

    // MARK: - 文字：随机排版

    struct TextLayout {
        let name: String
        let backgroundColor: UIColor
        let foregroundColor: UIColor
        let fontDesign: UIFontDescriptor.SystemDesign
        let fontWeight: UIFont.Weight
        let alignment: NSTextAlignment
        // 画布外侧留白，按短边比例计算。
        let paddingFraction: CGFloat
        // 行高倍数，影响多行文字的紧凑度。
        let lineHeightMultiple: CGFloat
    }

    // 排版库：调色克制，确保墨水屏 6 色映射后仍然可读。
    static let textLayouts: [TextLayout] = [
        TextLayout(
            name: "classic",
            backgroundColor: UIColor(white: 0.97, alpha: 1),
            foregroundColor: UIColor(white: 0.10, alpha: 1),
            fontDesign: .default,
            fontWeight: .bold,
            alignment: .center,
            paddingFraction: 0.10,
            lineHeightMultiple: 1.18
        ),
        TextLayout(
            name: "blueRounded",
            backgroundColor: UIColor(red: 0.18, green: 0.49, blue: 0.98, alpha: 1),
            foregroundColor: .white,
            fontDesign: .rounded,
            fontWeight: .semibold,
            alignment: .center,
            paddingFraction: 0.12,
            lineHeightMultiple: 1.22
        ),
        TextLayout(
            name: "warmSerif",
            backgroundColor: UIColor(red: 0.99, green: 0.96, blue: 0.88, alpha: 1),
            foregroundColor: UIColor(red: 0.30, green: 0.18, blue: 0.06, alpha: 1),
            fontDesign: .serif,
            fontWeight: .medium,
            alignment: .center,
            paddingFraction: 0.14,
            lineHeightMultiple: 1.28
        ),
        TextLayout(
            name: "darkHeadline",
            backgroundColor: UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1),
            foregroundColor: UIColor(red: 0.97, green: 0.94, blue: 0.78, alpha: 1),
            fontDesign: .default,
            fontWeight: .heavy,
            alignment: .center,
            paddingFraction: 0.10,
            lineHeightMultiple: 1.16
        ),
        TextLayout(
            name: "freshRounded",
            backgroundColor: UIColor(red: 0.94, green: 0.97, blue: 0.93, alpha: 1),
            foregroundColor: UIColor(red: 0.16, green: 0.34, blue: 0.20, alpha: 1),
            fontDesign: .rounded,
            fontWeight: .bold,
            alignment: .center,
            paddingFraction: 0.12,
            lineHeightMultiple: 1.20
        ),
        TextLayout(
            name: "peachSerif",
            backgroundColor: UIColor(red: 0.99, green: 0.91, blue: 0.84, alpha: 1),
            foregroundColor: UIColor(red: 0.50, green: 0.16, blue: 0.10, alpha: 1),
            fontDesign: .serif,
            fontWeight: .bold,
            alignment: .center,
            paddingFraction: 0.13,
            lineHeightMultiple: 1.24
        )
    ]

    // 没传 layout 就随机挑一个，每次调用结果不同。
    static func renderText(_ text: String, targetSize: CGSize, layout: TextLayout? = nil) -> UIImage {
        let chosenLayout = layout ?? textLayouts.randomElement() ?? textLayouts[0]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayText = trimmed.isEmpty ? " " : trimmed

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { context in
            chosenLayout.backgroundColor.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            let padding = min(targetSize.width, targetSize.height) * chosenLayout.paddingFraction
            let textArea = CGRect(
                x: padding,
                y: padding,
                width: max(0, targetSize.width - padding * 2),
                height: max(0, targetSize.height - padding * 2)
            )
            guard textArea.width > 0, textArea.height > 0 else { return }

            let result = bestFitFontSize(
                text: displayText,
                area: textArea.size,
                fontDesign: chosenLayout.fontDesign,
                fontWeight: chosenLayout.fontWeight,
                lineHeightMultiple: chosenLayout.lineHeightMultiple
            )

            let font = makeFont(size: result.size, design: chosenLayout.fontDesign, weight: chosenLayout.fontWeight)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = chosenLayout.alignment
            paragraph.lineHeightMultiple = chosenLayout.lineHeightMultiple
            paragraph.lineBreakMode = .byCharWrapping

            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: chosenLayout.foregroundColor,
                .paragraphStyle: paragraph
            ]

            let lineHeight = font.lineHeight * chosenLayout.lineHeightMultiple
            let totalHeight = CGFloat(result.lines.count) * lineHeight
            let startY = textArea.minY + max(0, (textArea.height - totalHeight) / 2)

            for (index, line) in result.lines.enumerated() {
                let lineRect = CGRect(
                    x: textArea.minX,
                    y: startY + CGFloat(index) * lineHeight,
                    width: textArea.width,
                    height: lineHeight
                )
                (line as NSString).draw(in: lineRect, withAttributes: attrs)
            }
        }
    }

    // MARK: - 内部：字号搜索 & 换行

    private static func makeFont(size: CGFloat, design: UIFontDescriptor.SystemDesign, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(design) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    // 优先在这些标点处换行：中英文逗号、句号、空格等。
    private static let breakCharacters: Set<Character> = [
        " ", "\t", "\n", "\u{3000}",
        ",", ".", ":", ";", "!", "?",
        "，", "。", "、", "；", "：", "！", "？",
        "·", "…", "—"
    ]

    // 把文字按"标点尾随"切成 token，断行时优先在 token 边界换行。
    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var buffer = ""
        for ch in text {
            if ch == "\n" {
                if !buffer.isEmpty {
                    tokens.append(buffer)
                    buffer = ""
                }
                tokens.append("\n")
                continue
            }
            buffer.append(ch)
            if breakCharacters.contains(ch) {
                tokens.append(buffer)
                buffer = ""
            }
        }
        if !buffer.isEmpty {
            tokens.append(buffer)
        }
        return tokens
    }

    private static func wrapLines(text: String, font: UIFont, maxWidth: CGFloat) -> [String] {
        guard maxWidth > 0 else { return [text] }

        let tokens = tokenize(text)
        var lines: [String] = []
        var current = ""

        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        func widthOf(_ string: String) -> CGFloat {
            (string as NSString).size(withAttributes: attrs).width
        }

        for token in tokens {
            if token == "\n" {
                lines.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            }
            let trial = current + token
            if widthOf(trial) <= maxWidth || current.isEmpty {
                current = trial
            } else {
                lines.append(current.trimmingCharacters(in: .whitespaces))
                current = token
            }
        }
        if !current.isEmpty {
            lines.append(current.trimmingCharacters(in: .whitespaces))
        }

        // 单 token 比 maxWidth 还宽时按字符兜底拆分，避免溢出。
        var refined: [String] = []
        for line in lines {
            if widthOf(line) <= maxWidth {
                refined.append(line)
            } else {
                refined.append(contentsOf: charWrap(line, font: font, maxWidth: maxWidth))
            }
        }
        return refined.isEmpty ? [""] : refined
    }

    private static func charWrap(_ text: String, font: UIFont, maxWidth: CGFloat) -> [String] {
        var lines: [String] = []
        var current = ""
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        for ch in text {
            let trial = current + String(ch)
            let width = (trial as NSString).size(withAttributes: attrs).width
            if width <= maxWidth || current.isEmpty {
                current = trial
            } else {
                lines.append(current)
                current = String(ch)
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines
    }

    private struct FitResult {
        let size: CGFloat
        let lines: [String]
    }

    // 从最大字号开始向下二分，直到文字刚好能放进 area。
    private static func bestFitFontSize(
        text: String,
        area: CGSize,
        fontDesign: UIFontDescriptor.SystemDesign,
        fontWeight: UIFont.Weight,
        lineHeightMultiple: CGFloat
    ) -> FitResult {
        let minSize: CGFloat = 14
        // 上限略大于画布短边，长句也能拿到合理初值。
        let maxSize = max(min(area.width, area.height), minSize + 1)

        // 先用最小字号确认一份兜底结果，避免极端情况下 lines 为空。
        let minFont = makeFont(size: minSize, design: fontDesign, weight: fontWeight)
        var bestSize = minSize
        var bestLines = wrapLines(text: text, font: minFont, maxWidth: area.width)

        var lo = minSize
        var hi = maxSize

        // 字号粒度按整数二分，最多 16 轮足够覆盖到 0~600pt。
        for _ in 0..<16 {
            if lo > hi { break }
            let mid = ((lo + hi) / 2).rounded()
            let font = makeFont(size: mid, design: fontDesign, weight: fontWeight)
            let lines = wrapLines(text: text, font: font, maxWidth: area.width)
            let totalHeight = CGFloat(lines.count) * font.lineHeight * lineHeightMultiple
            let widestLine = lines
                .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
                .max() ?? 0

            if totalHeight <= area.height && widestLine <= area.width {
                bestSize = mid
                bestLines = lines
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }

        return FitResult(size: bestSize, lines: bestLines)
    }
}
