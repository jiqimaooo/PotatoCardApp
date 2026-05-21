import UIKit

enum CircleUploadImageCompressor {
    static let maxDisplayImageBytes = 1_000_000

    enum CompressionError: LocalizedError {
        case jpegEncodingFailed

        var errorDescription: String? {
            switch self {
            case .jpegEncodingFailed:
                return "图片压缩失败，请重新选择"
            }
        }
    }

    /// 圈子上传使用的展示图压缩规则：优先降低 JPEG 质量；如果超大图仍大于 1M，
    /// 再按比例缩小像素尺寸，确保上传给服务端的展示图小于等于 1M。
    static func compressedDisplayJPEGData(
        from image: UIImage,
        maxBytes: Int = maxDisplayImageBytes
    ) throws -> Data {
        let qualitySteps: [CGFloat] = [0.82, 0.72, 0.62, 0.52, 0.42, 0.32, 0.24, 0.18]

        var currentImage = image
        var bestData: Data?

        for _ in 0..<8 {
            for quality in qualitySteps {
                guard let data = currentImage.jpegData(compressionQuality: quality) else {
                    continue
                }

                if bestData == nil || data.count < bestData!.count {
                    bestData = data
                }

                if data.count <= maxBytes {
                    return data
                }
            }

            guard let smallestData = bestData, currentImage.size.width > 64, currentImage.size.height > 64 else {
                break
            }

            let scale = max(0.45, min(0.92, sqrt(CGFloat(maxBytes) / CGFloat(smallestData.count)) * 0.92))
            let targetSize = CGSize(
                width: max(64, floor(currentImage.size.width * scale)),
                height: max(64, floor(currentImage.size.height * scale))
            )
            currentImage = resizedImage(currentImage, to: targetSize)
        }

        if let bestData, bestData.count <= maxBytes {
            return bestData
        }

        guard let fallbackData = currentImage.jpegData(compressionQuality: 0.12) else {
            throw CompressionError.jpegEncodingFailed
        }
        if fallbackData.count > maxBytes {
            throw CompressionError.jpegEncodingFailed
        }
        return fallbackData
    }

    private static func resizedImage(_ image: UIImage, to targetSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
