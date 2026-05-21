import CryptoKit
import UIKit

enum PotatoDevicePayloadCodec {
    struct BuildResult {
        let data: Data
        let meta: CirclePostPayloadMeta
        let transferImage: UIImage
    }

    enum PayloadError: LocalizedError {
        case invalidImage
        case invalidPayload

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "土豆片显示数据生成失败，请重试"
            case .invalidPayload:
                return "土豆片显示数据无法读取"
            }
        }
    }

    private struct PayloadHeader: Codable {
        let format: String
        let device: String
        let width: Int
        let height: Int
        let colorMode: String
        let encoding: String
        let palette: [[UInt8]]
    }

    private static let magic = Data("POTATO_PAYLOAD_V1\n".utf8)
    private static let format = "potato_payload_v1"
    private static let device = "potato_card"
    private static let colorMode = "six_color"
    private static let encoding = "palette_index_u8"
    static let targetSize = CGSize(width: 400, height: 600)

    // 与 EInkImageRenderer 的六色调色板保持一致。payload 只保存调色板索引，
    // 避免把 JPEG/PNG 这种展示格式误当成设备最终数据。
    private static let palette: [(red: UInt8, green: UInt8, blue: UInt8)] = [
        (255, 255, 255),
        (0, 0, 0),
        (255, 0, 0),
        (0, 160, 0),
        (0, 0, 255),
        (255, 255, 0),
    ]

    static func build(
        sourceImage: UIImage,
        adjustment: EInkManualAdjustment,
        ditherAlgorithm: EInkDitherAlgorithm
    ) throws -> BuildResult {
        let profile = EInkDeviceProfile.fallback
        let transferImage = EInkImageRenderer.renderForTransfer(
            image: sourceImage,
            targetSize: targetSize,
            fitMode: .manual,
            adjustment: adjustment,
            profile: profile,
            ditherAlgorithm: ditherAlgorithm
        )
        let payloadData = try encode(transferImage)
        let checksum = SHA256.hash(data: payloadData)
            .map { String(format: "%02x", $0) }
            .joined()
        let meta = CirclePostPayloadMeta(
            device: device,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            colorMode: colorMode,
            format: format,
            checksum: "sha256_\(checksum)",
            size: payloadData.count
        )
        return BuildResult(data: payloadData, meta: meta, transferImage: transferImage)
    }

    static func decodeImage(from data: Data) throws -> UIImage {
        guard data.starts(with: magic), data.count > magic.count + 4 else {
            throw PayloadError.invalidPayload
        }
        var cursor = magic.count
        let headerLength = Int(data.readBigEndianUInt32(at: cursor))
        cursor += 4
        guard headerLength > 0, data.count >= cursor + headerLength else {
            throw PayloadError.invalidPayload
        }

        let headerData = data.subdata(in: cursor..<(cursor + headerLength))
        cursor += headerLength
        let header = try JSONDecoder().decode(PayloadHeader.self, from: headerData)
        guard header.format == format,
              header.encoding == encoding,
              header.width > 0,
              header.height > 0,
              data.count >= cursor + header.width * header.height else {
            throw PayloadError.invalidPayload
        }

        let indices = data.subdata(in: cursor..<(cursor + header.width * header.height))
        var rgba = [UInt8](repeating: 255, count: header.width * header.height * 4)
        for pixelIndex in 0..<(header.width * header.height) {
            let colorIndex = min(Int(indices[pixelIndex]), palette.count - 1)
            let color = palette[colorIndex]
            let rgbaIndex = pixelIndex * 4
            rgba[rgbaIndex] = color.red
            rgba[rgbaIndex + 1] = color.green
            rgba[rgbaIndex + 2] = color.blue
            rgba[rgbaIndex + 3] = 255
        }
        return try imageFromRGBA(rgba, width: header.width, height: header.height)
    }

    private static func encode(_ image: UIImage) throws -> Data {
        guard let rgba = rgbaPixels(from: image) else {
            throw PayloadError.invalidImage
        }
        var indices = Data(capacity: Int(targetSize.width * targetSize.height))
        for pixelIndex in 0..<(rgba.width * rgba.height) {
            let base = pixelIndex * 4
            indices.append(nearestPaletteIndex(red: rgba.pixels[base], green: rgba.pixels[base + 1], blue: rgba.pixels[base + 2]))
        }

        let header = PayloadHeader(
            format: format,
            device: device,
            width: rgba.width,
            height: rgba.height,
            colorMode: colorMode,
            encoding: encoding,
            palette: palette.map { [$0.red, $0.green, $0.blue] }
        )
        let headerData = try JSONEncoder().encode(header)
        var payload = Data()
        payload.append(magic)
        payload.appendBigEndianUInt32(UInt32(headerData.count))
        payload.append(headerData)
        payload.append(indices)
        return payload
    }

    private static func rgbaPixels(from image: UIImage) -> (pixels: [UInt8], width: Int, height: Int)? {
        guard let cgImage = image.cgImage else { return nil }
        let width = Int(targetSize.width)
        let height = Int(targetSize.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 255, count: height * bytesPerRow)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress else { return false }
            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return didDraw ? (pixels, width, height) : nil
    }

    private static func nearestPaletteIndex(red: UInt8, green: UInt8, blue: UInt8) -> UInt8 {
        let target = (red: Double(red), green: Double(green), blue: Double(blue))
        let bestIndex = palette.indices.min { lhs, rhs in
            weightedDistance(from: target, to: palette[lhs]) < weightedDistance(from: target, to: palette[rhs])
        } ?? 0
        return UInt8(bestIndex)
    }

    private static func weightedDistance(
        from lhs: (red: Double, green: Double, blue: Double),
        to rhs: (red: UInt8, green: UInt8, blue: UInt8)
    ) -> Double {
        let redDelta = lhs.red - Double(rhs.red)
        let greenDelta = lhs.green - Double(rhs.green)
        let blueDelta = lhs.blue - Double(rhs.blue)
        return redDelta * redDelta * 0.30 + greenDelta * greenDelta * 0.59 + blueDelta * blueDelta * 0.11
    }

    private static func imageFromRGBA(_ pixels: [UInt8], width: Int, height: Int) throws -> UIImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw PayloadError.invalidPayload
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}

private extension Data {
    mutating func appendBigEndianUInt32(_ value: UInt32) {
        var bigEndianValue = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndianValue) { append(contentsOf: $0) }
    }

    func readBigEndianUInt32(at offset: Int) -> UInt32 {
        guard count >= offset + 4 else { return 0 }
        return self[offset..<(offset + 4)].reduce(UInt32(0)) { result, byte in
            (result << 8) | UInt32(byte)
        }
    }
}
