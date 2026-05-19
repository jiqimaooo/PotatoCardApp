import UIKit

enum EInkImageFitMode: String, CaseIterable, Identifiable {
    case centerCrop
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .centerCrop:
            return "居中裁切"
        case .manual:
            return "手动调整"
        }
    }
}

struct EInkManualAdjustment: Equatable {
    var scale: CGFloat = 1
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    // 旋转角度（弧度），绕图片中心转动。
    var rotation: CGFloat = 0

    static let `default` = EInkManualAdjustment()
}

enum EInkDitherAlgorithm: String, CaseIterable, Identifiable, Codable {
    case floydSteinberg
    case atkinson
    case sierraLite
    case bayer8x8
    case nearestColor
    case originalBW
    case originalBWRY
    case original7Color
    case original6Color
    case original1600Split

    var id: String { rawValue }

    var title: String {
        switch self {
        case .floydSteinberg:
            return "Floyd-Steinberg"
        case .atkinson:
            return "Atkinson"
        case .sierraLite:
            return "Sierra Lite"
        case .bayer8x8:
            return "Bayer 8x8"
        case .nearestColor:
            return "Nearest Color"
        case .originalBW:
            return "原始算法 1"
        case .originalBWRY:
            return "原始算法 2"
        case .original7Color:
            return "原始算法 3"
        case .original6Color:
            return "原始算法 4"
        case .original1600Split:
            return "原始算法 5"
        }
    }

    var subtitle: String {
        switch self {
        case .floydSteinberg:
            return "当前默认，细节最多"
        case .atkinson:
            return "更柔和，适合人像"
        case .sierraLite:
            return "噪点较少，速度轻快"
        case .bayer8x8:
            return "规则网格，适合插画文字"
        case .nearestColor:
            return "不抖动，直接映射 6 色"
        case .originalBW:
            return "原始黑白调色板 + Floyd 抖动"
        case .originalBWRY:
            return "原始黑白红黄调色板 + Floyd 抖动"
        case .original7Color:
            return "原始 7/8 色调色板 + Floyd 抖动"
        case .original6Color:
            return "原始 6 色调色板 + Floyd 抖动"
        case .original1600Split:
            return "1600x1200 原始 6 色 + Floyd 抖动"
        }
    }

    var isOriginalColorMapping: Bool {
        switch self {
        case .originalBW, .originalBWRY, .original7Color, .original6Color, .original1600Split:
            return true
        case .floydSteinberg, .atkinson, .sierraLite, .bayer8x8, .nearestColor:
            return false
        }
    }
}

enum EInkImageRenderer {
    static func render(
        image: UIImage,
        targetSize: CGSize,
        fitMode: EInkImageFitMode,
        adjustment: EInkManualAdjustment = .default
    ) -> UIImage {
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            // baseRect 只算「baseScale * manualScale 居中放置」的矩形，**不带 offset**。
            // offset 改为通过 CGContext 平移叠加，并且**放在 rotate 的外层**，
            // 这样最终像素变换 = T(offset) ∘ R(rotation, around center) ∘ draw(baseRect)，
            // 与 SwiftUI 预览的 `.scaleEffect → .rotationEffect → .offset` 顺序完全一致。
            // 之前的实现是把 offset 写进 baseRect.origin 再整体旋转，等价于让 offset 也跟着
            // 旋转 → 用户在编辑界面看到的位置和实际传出去的图位置对不上。
            let baseRect = baseDrawRect(
                for: image.size,
                targetSize: targetSize,
                fitMode: fitMode,
                adjustment: adjustment
            )

            let rotation = fitMode == .manual ? adjustment.rotation : 0
            let offsetX = fitMode == .manual ? adjustment.offsetX : 0
            let offsetY = fitMode == .manual ? adjustment.offsetY : 0

            if rotation != 0 || offsetX != 0 || offsetY != 0 {
                let cgContext = context.cgContext
                cgContext.saveGState()
                // CGContext 变换合成顺序：后调用的更靠近「画笔」，
                // 所以这里先 translate(offset) → 再 rotate，等价于「先把 baseRect 围绕画布中心旋转，
                // 再做不旋转的平移」（== SwiftUI 的 rotationEffect → offset）。
                cgContext.translateBy(x: offsetX, y: offsetY)
                if rotation != 0 {
                    cgContext.translateBy(x: targetSize.width / 2, y: targetSize.height / 2)
                    cgContext.rotate(by: rotation)
                    cgContext.translateBy(x: -targetSize.width / 2, y: -targetSize.height / 2)
                }
                image.draw(in: baseRect)
                cgContext.restoreGState()
            } else {
                // 默认情况：没有 offset / rotation，走最简单的路径，避免不必要的 GState push/pop。
                image.draw(in: baseRect)
            }
        }
    }

    static func renderForTransfer(
        image: UIImage,
        targetSize: CGSize,
        fitMode: EInkImageFitMode,
        adjustment: EInkManualAdjustment = .default,
        profile: EInkDeviceProfile,
        ditherAlgorithm: EInkDitherAlgorithm = .floydSteinberg
    ) -> UIImage {
        let fittedImage = render(
            image: image,
            targetSize: targetSize,
            fitMode: fitMode,
            adjustment: adjustment
        )
        let rotatedImage = fittedImage.rotated180ForEInkTransfer()

        if ditherAlgorithm.isOriginalColorMapping {
            return renderOriginalColorMapping(rotatedImage, algorithm: ditherAlgorithm)
        }

        switch profile.colorMode {
        case .sixColor:
            return renderSixColor(rotatedImage, algorithm: ditherAlgorithm)
        case .monochrome, .blackWhiteRed, .blackWhiteRedYellow:
            return rotatedImage
        }
    }

    // 只计算「baseScale * manualScale 居中放置」后的矩形，**不带 offset**。
    // offset 由调用方在 CGContext 上平移叠加，且必须放在 rotate 的外层，
    // 才能与 SwiftUI 预览里 `.rotationEffect → .offset` 的几何顺序一致。
    private static func baseDrawRect(
        for imageSize: CGSize,
        targetSize: CGSize,
        fitMode: EInkImageFitMode,
        adjustment: EInkManualAdjustment
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: targetSize)
        }

        let baseScale = max(targetSize.width / imageSize.width, targetSize.height / imageSize.height)
        let manualScale = fitMode == .manual ? adjustment.scale : 1
        let finalSize = CGSize(
            width: imageSize.width * baseScale * manualScale,
            height: imageSize.height * baseScale * manualScale
        )

        let origin = CGPoint(
            x: (targetSize.width - finalSize.width) / 2,
            y: (targetSize.height - finalSize.height) / 2
        )

        return CGRect(origin: origin, size: finalSize)
    }

    private static func renderSixColor(_ image: UIImage, algorithm: EInkDitherAlgorithm) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return image }

        guard let context = SixColorBitmapContext(cgImage: cgImage, width: width, height: height) else {
            return image
        }

        switch algorithm {
        case .nearestColor:
            applyNearestColor(to: &context.pixels, width: width, height: height)
        case .bayer8x8:
            applyBayer8x8(to: &context.pixels, width: width, height: height)
        case .floydSteinberg:
            applyErrorDiffusion(to: &context.pixels, width: width, height: height, kernel: EInkDiffusionKernel.floydSteinberg)
        case .atkinson:
            applyErrorDiffusion(to: &context.pixels, width: width, height: height, kernel: EInkDiffusionKernel.atkinson)
        case .sierraLite:
            applyErrorDiffusion(to: &context.pixels, width: width, height: height, kernel: EInkDiffusionKernel.sierraLite)
        case .originalBW, .originalBWRY, .original7Color, .original6Color, .original1600Split:
            applyOriginalColorMapping(to: &context.pixels, width: width, height: height, algorithm: algorithm)
        }

        guard let provider = CGDataProvider(data: Data(context.pixels) as CFData),
              let output = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: context.bytesPerRow,
                space: context.colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: context.bitmapInfo),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              )
        else {
            return image
        }

        return UIImage(cgImage: output, scale: 1, orientation: .up)
    }

    private static func renderOriginalColorMapping(_ image: UIImage, algorithm: EInkDitherAlgorithm) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return image }

        guard let context = SixColorBitmapContext(cgImage: cgImage, width: width, height: height) else {
            return image
        }

        applyOriginalPreDitherEnhancement(to: &context.pixels, algorithm: algorithm)

        // convert.js 里的原始算法本身是硬阈值映射，照片会丢大量灰阶。
        // 这里保留原始颜色集合，但先用 Floyd-Steinberg 扩散误差，让真机照片保留更多层次。
        applyErrorDiffusion(
            to: &context.pixels,
            width: width,
            height: height,
            kernel: EInkDiffusionKernel.floydSteinberg,
            palette: originalPalette(for: algorithm)
        )

        guard let provider = CGDataProvider(data: Data(context.pixels) as CFData),
              let output = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: context.bytesPerRow,
                space: context.colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: context.bitmapInfo),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              )
        else {
            return image
        }

        return UIImage(cgImage: output, scale: 1, orientation: .up)
    }

    private static func applyNearestColor(to pixels: inout [UInt8], width: Int, height: Int) {
        let palette = EInkSixColorPalette.colors
        for pixelIndex in 0..<(width * height) {
            let sourceIndex = pixelIndex * 4
            let current = EInkDitherColor(
                red: Double(pixels[sourceIndex]),
                green: Double(pixels[sourceIndex + 1]),
                blue: Double(pixels[sourceIndex + 2])
            )
            let replacement = nearestPaletteColor(to: current, in: palette)
            write(replacement, to: &pixels, pixelIndex: pixelIndex)
        }
    }

    private static func applyBayer8x8(to pixels: inout [UInt8], width: Int, height: Int) {
        let palette = EInkSixColorPalette.colors

        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * width + x
                let sourceIndex = pixelIndex * 4
                let threshold = (Double(EInkBayerMatrix.eightByEight[y % 8][x % 8]) + 0.5) / 64.0 - 0.5
                let offset = threshold * 72.0
                let current = EInkDitherColor(
                    red: (Double(pixels[sourceIndex]) + offset).clampedToByteRange,
                    green: (Double(pixels[sourceIndex + 1]) + offset).clampedToByteRange,
                    blue: (Double(pixels[sourceIndex + 2]) + offset).clampedToByteRange
                )
                let replacement = nearestPaletteColor(to: current, in: palette)
                write(replacement, to: &pixels, pixelIndex: pixelIndex)
            }
        }
    }

    private static func applyOriginalColorMapping(
        to pixels: inout [UInt8],
        width: Int,
        height: Int,
        algorithm: EInkDitherAlgorithm
    ) {
        for pixelIndex in 0..<(width * height) {
            let sourceIndex = pixelIndex * 4
            let red = pixels[sourceIndex]
            let green = pixels[sourceIndex + 1]
            let blue = pixels[sourceIndex + 2]
            let color = originalMappedColor(red: red, green: green, blue: blue, algorithm: algorithm)
            write(color, to: &pixels, pixelIndex: pixelIndex)
        }
    }

    private static func originalPalette(for algorithm: EInkDitherAlgorithm) -> [EInkDitherColor] {
        switch algorithm {
        case .originalBW:
            return [
                EInkOriginalColorCode.black.color,
                EInkOriginalColorCode.white.color
            ]
        case .originalBWRY:
            return [
                EInkOriginalColorCode.black.color,
                EInkOriginalColorCode.white.color,
                EInkOriginalColorCode.red.color,
                EInkOriginalColorCode.yellow.color
            ]
        case .original7Color:
            return [
                EInkOriginalColorCode.black.color,
                EInkOriginalColorCode.white.color,
                EInkOriginalColorCode.yellow.color,
                EInkOriginalColorCode.red.color,
                EInkOriginalColorCode.orange.color,
                EInkOriginalColorCode.blue.color,
                EInkOriginalColorCode.green.color
            ]
        case .original6Color, .original1600Split:
            return [
                EInkOriginalColorCode.black.color,
                EInkOriginalColorCode.white.color,
                EInkOriginalColorCode.yellow.color,
                EInkOriginalColorCode.red.color,
                EInkOriginalColorCode.blue.color,
                EInkOriginalColorCode.green.color
            ]
        case .floydSteinberg, .atkinson, .sierraLite, .bayer8x8, .nearestColor:
            return EInkSixColorPalette.colors
        }
    }

    private static func applyOriginalPreDitherEnhancement(to pixels: inout [UInt8], algorithm: EInkDitherAlgorithm) {
        guard let profile = originalEnhancementProfile(for: algorithm) else { return }

        for pixelIndex in 0..<(pixels.count / 4) {
            let sourceIndex = pixelIndex * 4
            var red = Double(pixels[sourceIndex])
            var green = Double(pixels[sourceIndex + 1])
            var blue = Double(pixels[sourceIndex + 2])

            let luminance = red * 0.30 + green * 0.59 + blue * 0.11
            red = luminance + (red - luminance) * profile.saturation
            green = luminance + (green - luminance) * profile.saturation
            blue = luminance + (blue - luminance) * profile.saturation

            red = ((red - 128) * profile.contrast + 128 + profile.brightness).clampedToByteRange
            green = ((green - 128) * profile.contrast + 128 + profile.brightness).clampedToByteRange
            blue = ((blue - 128) * profile.contrast + 128 + profile.brightness).clampedToByteRange

            // 小程序输出更深，传输前压暗中间调，减少真机上发灰发浅的问题。
            red = pow(red / 255, profile.gamma) * 255
            green = pow(green / 255, profile.gamma) * 255
            blue = pow(blue / 255, profile.gamma) * 255

            pixels[sourceIndex] = UInt8(red.clampedToByteRange.rounded())
            pixels[sourceIndex + 1] = UInt8(green.clampedToByteRange.rounded())
            pixels[sourceIndex + 2] = UInt8(blue.clampedToByteRange.rounded())
        }
    }

    private static func originalEnhancementProfile(for algorithm: EInkDitherAlgorithm) -> EInkOriginalEnhancementProfile? {
        switch algorithm {
        case .original6Color, .original1600Split:
            return EInkOriginalEnhancementProfile(contrast: 1.22, saturation: 1.48, brightness: -10, gamma: 1.08)
        case .original7Color:
            return EInkOriginalEnhancementProfile(contrast: 1.16, saturation: 1.32, brightness: -6, gamma: 1.05)
        case .originalBWRY:
            return EInkOriginalEnhancementProfile(contrast: 1.12, saturation: 1.18, brightness: -4, gamma: 1.03)
        case .originalBW, .floydSteinberg, .atkinson, .sierraLite, .bayer8x8, .nearestColor:
            return nil
        }
    }

    private static func originalMappedColor(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        algorithm: EInkDitherAlgorithm
    ) -> EInkDitherColor {
        let threshold: UInt8 = 128
        let redOn = red > threshold
        let greenOn = green > threshold
        let blueOn = blue > threshold

        switch algorithm {
        case .originalBW:
            return originalLuminance(red: red, green: green, blue: blue) > Double(threshold)
                ? EInkOriginalColorCode.white.color
                : EInkOriginalColorCode.black.color
        case .originalBWRY:
            return originalBWRYColor(
                red: red,
                green: green,
                blue: blue,
                redOn: redOn,
                greenOn: greenOn,
                blueOn: blueOn
            )
        case .original7Color:
            return original7Color(
                red: red,
                green: green,
                blue: blue,
                redOn: redOn,
                greenOn: greenOn,
                blueOn: blueOn
            )
        case .original6Color, .original1600Split:
            // convertColors1600x1200 的差异主要是字节分屏排列；当前 SDK 接收 UIImage，
            // 所以视觉颜色映射与 convertColors 保持一致，由 SDK 继续负责底层打包。
            return original6Color(redOn: redOn, greenOn: greenOn, blueOn: blueOn)
        case .floydSteinberg, .atkinson, .sierraLite, .bayer8x8, .nearestColor:
            return EInkDitherColor(red: Double(red), green: Double(green), blue: Double(blue))
        }
    }

    private static func originalBWRYColor(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        redOn: Bool,
        greenOn: Bool,
        blueOn: Bool
    ) -> EInkDitherColor {
        if redOn && greenOn && !blueOn {
            return EInkOriginalColorCode.yellow.color
        }

        if redOn && !greenOn && !blueOn {
            return EInkOriginalColorCode.red.color
        }

        return originalLuminance(red: red, green: green, blue: blue) > 128
            ? EInkOriginalColorCode.white.color
            : EInkOriginalColorCode.black.color
    }

    private static func original7Color(
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        redOn: Bool,
        greenOn: Bool,
        blueOn: Bool
    ) -> EInkDitherColor {
        if !redOn && !greenOn && !blueOn {
            return EInkOriginalColorCode.black.color
        }

        if redOn && greenOn && blueOn {
            return EInkOriginalColorCode.white.color
        }

        if redOn && !blueOn {
            if green > 0xA5 {
                return EInkOriginalColorCode.yellow.color
            }
            if green > 0x45 {
                return EInkOriginalColorCode.orange.color
            }
            return EInkOriginalColorCode.red.color
        }

        if !redOn && greenOn && !blueOn {
            return EInkOriginalColorCode.green.color
        }

        if !redOn && !greenOn && blueOn {
            return EInkOriginalColorCode.blue.color
        }

        return EInkOriginalColorCode.white.color
    }

    private static func original6Color(redOn: Bool, greenOn: Bool, blueOn: Bool) -> EInkDitherColor {
        if !redOn && !greenOn && !blueOn {
            return EInkOriginalColorCode.black.color
        }

        if redOn && greenOn && blueOn {
            return EInkOriginalColorCode.white.color
        }

        if redOn && greenOn && !blueOn {
            return EInkOriginalColorCode.yellow.color
        }

        if redOn && !greenOn && !blueOn {
            return EInkOriginalColorCode.red.color
        }

        if !redOn && !greenOn && blueOn {
            return EInkOriginalColorCode.blue.color
        }

        if !redOn && greenOn && !blueOn {
            return EInkOriginalColorCode.green.color
        }

        return EInkOriginalColorCode.white.color
    }

    private static func originalLuminance(red: UInt8, green: UInt8, blue: UInt8) -> Double {
        // convert.js 的 lumG 看起来少了小数点；这里按常规 0.30/0.59/0.11 灰度权重复刻阈值意图。
        Double(red) * 0.30 + Double(green) * 0.59 + Double(blue) * 0.11
    }

    private static func applyErrorDiffusion(
        to pixels: inout [UInt8],
        width: Int,
        height: Int,
        kernel: [EInkDiffusionStep],
        palette: [EInkDitherColor] = EInkSixColorPalette.colors
    ) {
        let bytesPerPixel = 4
        var working = [Double](repeating: 0, count: width * height * 3)
        for pixelIndex in 0..<(width * height) {
            let sourceIndex = pixelIndex * bytesPerPixel
            let workIndex = pixelIndex * 3
            working[workIndex] = Double(pixels[sourceIndex])
            working[workIndex + 1] = Double(pixels[sourceIndex + 1])
            working[workIndex + 2] = Double(pixels[sourceIndex + 2])
        }

        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * width + x
                let workIndex = pixelIndex * 3
                let current = EInkDitherColor(
                    red: working[workIndex].clampedToByteRange,
                    green: working[workIndex + 1].clampedToByteRange,
                    blue: working[workIndex + 2].clampedToByteRange
                )
                let replacement = nearestPaletteColor(to: current, in: palette)
                let error = EInkDitherColor(
                    red: current.red - replacement.red,
                    green: current.green - replacement.green,
                    blue: current.blue - replacement.blue
                )

                pixels[pixelIndex * bytesPerPixel] = UInt8(replacement.red.rounded())
                pixels[pixelIndex * bytesPerPixel + 1] = UInt8(replacement.green.rounded())
                pixels[pixelIndex * bytesPerPixel + 2] = UInt8(replacement.blue.rounded())
                pixels[pixelIndex * bytesPerPixel + 3] = 255

                for step in kernel {
                    diffuse(
                        error,
                        x: x + step.x,
                        y: y + step.y,
                        width: width,
                        height: height,
                        factor: step.factor,
                        pixels: &working
                    )
                }
            }
        }
    }

    private static func write(_ color: EInkDitherColor, to pixels: inout [UInt8], pixelIndex: Int) {
        let index = pixelIndex * 4
        pixels[index] = UInt8(color.red.rounded())
        pixels[index + 1] = UInt8(color.green.rounded())
        pixels[index + 2] = UInt8(color.blue.rounded())
        pixels[index + 3] = 255
    }

    private static func nearestPaletteColor(to color: EInkDitherColor, in palette: [EInkDitherColor]) -> EInkDitherColor {
        palette.min { lhs, rhs in
            weightedDistance(from: color, to: lhs) < weightedDistance(from: color, to: rhs)
        } ?? palette[0]
    }

    private static func weightedDistance(from lhs: EInkDitherColor, to rhs: EInkDitherColor) -> Double {
        let redDelta = lhs.red - rhs.red
        let greenDelta = lhs.green - rhs.green
        let blueDelta = lhs.blue - rhs.blue
        return redDelta * redDelta * 0.30 + greenDelta * greenDelta * 0.59 + blueDelta * blueDelta * 0.11
    }

    private static func diffuse(
        _ error: EInkDitherColor,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        factor: Double,
        pixels: inout [Double]
    ) {
        guard x >= 0, x < width, y >= 0, y < height else { return }

        let index = (y * width + x) * 3
        pixels[index] = (pixels[index] + error.red * factor).clampedToByteRange
        pixels[index + 1] = (pixels[index + 1] + error.green * factor).clampedToByteRange
        pixels[index + 2] = (pixels[index + 2] + error.blue * factor).clampedToByteRange
    }
}

private struct EInkDitherColor {
    let red: Double
    let green: Double
    let blue: Double
}

private struct EInkDiffusionStep {
    let x: Int
    let y: Int
    let factor: Double
}

private struct EInkOriginalEnhancementProfile {
    let contrast: Double
    let saturation: Double
    let brightness: Double
    let gamma: Double
}

private enum EInkDiffusionKernel {
    static let floydSteinberg = [
        EInkDiffusionStep(x: 1, y: 0, factor: 7.0 / 16.0),
        EInkDiffusionStep(x: -1, y: 1, factor: 3.0 / 16.0),
        EInkDiffusionStep(x: 0, y: 1, factor: 5.0 / 16.0),
        EInkDiffusionStep(x: 1, y: 1, factor: 1.0 / 16.0)
    ]

    static let atkinson = [
        EInkDiffusionStep(x: 1, y: 0, factor: 1.0 / 8.0),
        EInkDiffusionStep(x: 2, y: 0, factor: 1.0 / 8.0),
        EInkDiffusionStep(x: -1, y: 1, factor: 1.0 / 8.0),
        EInkDiffusionStep(x: 0, y: 1, factor: 1.0 / 8.0),
        EInkDiffusionStep(x: 1, y: 1, factor: 1.0 / 8.0),
        EInkDiffusionStep(x: 0, y: 2, factor: 1.0 / 8.0)
    ]

    static let sierraLite = [
        EInkDiffusionStep(x: 1, y: 0, factor: 2.0 / 4.0),
        EInkDiffusionStep(x: -1, y: 1, factor: 1.0 / 4.0),
        EInkDiffusionStep(x: 0, y: 1, factor: 1.0 / 4.0)
    ]
}

private enum EInkBayerMatrix {
    static let eightByEight = [
        [0, 48, 12, 60, 3, 51, 15, 63],
        [32, 16, 44, 28, 35, 19, 47, 31],
        [8, 56, 4, 52, 11, 59, 7, 55],
        [40, 24, 36, 20, 43, 27, 39, 23],
        [2, 50, 14, 62, 1, 49, 13, 61],
        [34, 18, 46, 30, 33, 17, 45, 29],
        [10, 58, 6, 54, 9, 57, 5, 53],
        [42, 26, 38, 22, 41, 25, 37, 21]
    ]
}

private final class SixColorBitmapContext {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let colorSpace: CGColorSpace
    let bitmapInfo: UInt32
    var pixels: [UInt8]

    init?(cgImage: CGImage, width: Int, height: Int) {
        self.width = width
        self.height = height
        self.bytesPerRow = width * 4
        self.colorSpace = CGColorSpaceCreateDeviceRGB()
        self.bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        self.pixels = [UInt8](repeating: 255, count: height * bytesPerRow)

        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress else { return false }
            let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
            context?.interpolationQuality = .none
            context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return context != nil
        }

        guard didDraw else { return nil }
    }
}

private enum EInkOriginalColorCode: Int {
    case black = 0
    case white = 1
    case yellow = 2
    case red = 3
    case orange = 4
    case blue = 5
    case green = 6

    var color: EInkDitherColor {
        switch self {
        case .black:
            return EInkDitherColor(red: 0, green: 0, blue: 0)
        case .white:
            return EInkDitherColor(red: 255, green: 255, blue: 255)
        case .yellow:
            return EInkDitherColor(red: 255, green: 255, blue: 0)
        case .red:
            return EInkDitherColor(red: 255, green: 0, blue: 0)
        case .orange:
            return EInkDitherColor(red: 255, green: 128, blue: 0)
        case .blue:
            return EInkDitherColor(red: 0, green: 0, blue: 255)
        case .green:
            return EInkDitherColor(red: 0, green: 255, blue: 0)
        }
    }
}

private enum EInkSixColorPalette {
    static let colors = [
        EInkDitherColor(red: 255, green: 255, blue: 255),
        EInkDitherColor(red: 0, green: 0, blue: 0),
        EInkDitherColor(red: 255, green: 0, blue: 0),
        EInkDitherColor(red: 0, green: 160, blue: 0),
        EInkDitherColor(red: 0, green: 0, blue: 255),
        EInkDitherColor(red: 255, green: 255, blue: 0)
    ]
}

private extension UIImage {
    func rotated180ForEInkTransfer() -> UIImage {
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: rendererFormat)
        return renderer.image { context in
            context.cgContext.translateBy(x: size.width, y: size.height)
            context.cgContext.rotate(by: .pi)
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private extension Double {
    var clampedToByteRange: Double {
        min(max(self, 0), 255)
    }
}
