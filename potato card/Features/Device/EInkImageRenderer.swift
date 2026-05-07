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

            let drawRect = drawRect(
                for: image.size,
                targetSize: targetSize,
                fitMode: fitMode,
                adjustment: adjustment
            )

            // 只在“手动调整”模式下应用旋转，避免给 .centerCrop 加上不期望的变换。
            // 绕画布中心转动 -> drawRect 仍以未旋转的坐标计算，与预览中 .rotationEffect 的默认锤点保持一致。
            let rotation = fitMode == .manual ? adjustment.rotation : 0
            if rotation != 0 {
                let cgContext = context.cgContext
                cgContext.saveGState()
                cgContext.translateBy(x: targetSize.width / 2, y: targetSize.height / 2)
                cgContext.rotate(by: rotation)
                cgContext.translateBy(x: -targetSize.width / 2, y: -targetSize.height / 2)
                image.draw(in: drawRect)
                cgContext.restoreGState()
            } else {
                // 直接绘制到目标尺寸，避免先把 iPhone 原图完整解码成超大位图。
                image.draw(in: drawRect)
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

        switch profile.colorMode {
        case .sixColor:
            return renderSixColor(rotatedImage, algorithm: ditherAlgorithm)
        case .monochrome, .blackWhiteRed, .blackWhiteRedYellow:
            return rotatedImage
        }
    }

    private static func drawRect(
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
            x: (targetSize.width - finalSize.width) / 2 + (fitMode == .manual ? adjustment.offsetX : 0),
            y: (targetSize.height - finalSize.height) / 2 + (fitMode == .manual ? adjustment.offsetY : 0)
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

    private static func applyErrorDiffusion(
        to pixels: inout [UInt8],
        width: Int,
        height: Int,
        kernel: [EInkDiffusionStep]
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

        let palette = EInkSixColorPalette.colors

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
