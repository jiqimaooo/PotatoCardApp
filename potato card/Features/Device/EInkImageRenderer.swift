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

    static let `default` = EInkManualAdjustment()
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
            // 直接绘制到目标尺寸，避免先把 iPhone 原图完整解码成超大位图。
            image.draw(in: drawRect)
        }
    }

    static func renderForTransfer(
        image: UIImage,
        targetSize: CGSize,
        fitMode: EInkImageFitMode,
        adjustment: EInkManualAdjustment = .default,
        profile: EInkDeviceProfile
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
            return ditherSixColor(rotatedImage)
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

    private static func ditherSixColor(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return image }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        var pixels = [UInt8](repeating: 255, count: height * bytesPerRow)

        pixels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
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
        }

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

                diffuse(error, x: x + 1, y: y, width: width, height: height, factor: 7.0 / 16.0, pixels: &working)
                diffuse(error, x: x - 1, y: y + 1, width: width, height: height, factor: 3.0 / 16.0, pixels: &working)
                diffuse(error, x: x, y: y + 1, width: width, height: height, factor: 5.0 / 16.0, pixels: &working)
                diffuse(error, x: x + 1, y: y + 1, width: width, height: height, factor: 1.0 / 16.0, pixels: &working)
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let output = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
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
