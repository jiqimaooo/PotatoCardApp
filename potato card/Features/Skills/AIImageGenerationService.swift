import Foundation
import Photos
import UIKit

struct GeneratedAIImage {
    let image: UIImage
    let pngData: Data
    let title: String
}

@MainActor
final class AIImageGenerationService {
    func generate(
        prompt inputPrompt: String,
        provider overrideProvider: AIImageModelProvider? = nil,
        size overrideSize: AIImageSize? = nil,
        saveToAppGallery: Bool,
        saveToSystemPhotos: Bool = false
    ) async throws -> GeneratedAIImage {
        let trimmedInput = inputPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { throw AIImageGenerationError.missingPrompt }

        let config = AISkillSettingsStore.loadConfiguration()
        let providerKind = overrideProvider ?? config.provider
        let model: String
        if let overrideProvider, overrideProvider != config.provider {
            // 快捷指令临时切换服务时，避免沿用另一个服务的模型名导致请求失败。
            model = overrideProvider.defaultModel
        } else {
            model = config.defaultModel.isEmpty ? providerKind.defaultModel : config.defaultModel
        }
        let size = overrideSize ?? config.defaultSize
        let prompt = Self.renderPrompt(input: trimmedInput, template: config.promptTemplate)
        let apiKey = (try? KeychainService.read(key: providerKind.keychainKey))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !apiKey.isEmpty else {
            throw AIImageGenerationError.missingAPIKey(providerKind.title)
        }

        let request = AIImageGenerationRequest(
            prompt: prompt,
            model: model,
            size: size,
            apiKey: apiKey,
            timeoutInterval: 120,
            debugLog: nil
        )
        let provider = AIImageProviderFactory.provider(for: providerKind)
        let sourceData: Data
        do {
            sourceData = try await provider.generateImageData(request: request)
        } catch {
            throw AIImageErrorParser.parse(error, provider: providerKind)
        }
        guard let sourceImage = UIImage(data: sourceData) else {
            throw AIImageGenerationError.invalidImageData
        }

        // 所有 AI 输出先统一成土豆片屏幕比例，避免不同服务返回尺寸差异影响后续传输。
        let normalizedImage = EInkImageRenderer.render(
            image: sourceImage,
            targetSize: size.cgSize,
            fitMode: .centerCrop
        )
        guard let pngData = normalizedImage.pngData() else {
            throw AIImageGenerationError.invalidImageData
        }

        let title = Self.galleryTitle(from: trimmedInput)
        if saveToAppGallery {
            _ = GalleryCacheStore.appendPhoto(data: pngData, title: title)
        }
        if saveToSystemPhotos {
            try await PhotoLibrarySaver.save(normalizedImage)
        }
        if config.autoTransferToDevice {
            _ = try await CardPushCoordinator.shared.pushImage(normalizedImage, shouldSaveToGalleryOverride: false)
        }

        return GeneratedAIImage(image: normalizedImage, pngData: pngData, title: title)
    }

    func testAPI(debugLog: AIImageDebugLogger? = nil) async throws {
        debugLog?("读取 AI 生图配置")
        let config = AISkillSettingsStore.loadConfiguration()
        let providerKind = config.provider
        let model = config.defaultModel.isEmpty ? providerKind.defaultModel : config.defaultModel
        debugLog?("当前服务：\(providerKind.title)")
        debugLog?("当前模型：\(model)")
        debugLog?("读取 Keychain API Key")
        let apiKey = (try? KeychainService.read(key: providerKind.keychainKey))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !apiKey.isEmpty else {
            debugLog?("API Key 为空，终止测试")
            throw AIImageGenerationError.missingAPIKey(providerKind.title)
        }
        debugLog?("API Key 已读取，长度 \(apiKey.count)")

        let request = AIImageGenerationRequest(
            // 测试只验证鉴权、模型和返回图片链路，不写入图库，也不触发设备传输。
            prompt: "A simple clean test image for API connectivity.",
            model: model,
            size: config.defaultSize,
            apiKey: apiKey,
            timeoutInterval: 20,
            debugLog: debugLog
        )
        let provider = AIImageProviderFactory.provider(for: providerKind)
        do {
            debugLog?("开始调用模型服务")
            let data = try await withTimeout(seconds: 25, debugLog: debugLog) {
                try await provider.generateImageData(request: request)
            }
            debugLog?("模型服务返回数据：\(data.count) bytes")
            guard UIImage(data: data) != nil else {
                debugLog?("返回数据不是可解析图片")
                throw AIImageGenerationError.invalidImageData
            }
            debugLog?("图片数据解析成功，API 测试完成")
        } catch {
            debugLog?("测试失败：\(error.localizedDescription)")
            throw AIImageErrorParser.parse(error, provider: providerKind)
        }
    }

    private func withTimeout<T>(
        seconds: TimeInterval,
        debugLog: AIImageDebugLogger?,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                await debugLog?("测试 API 超过 \(Int(seconds)) 秒未返回，主动结束")
                throw AIImageGenerationError.remote("请求超时", rawLog: "AI image API test timed out after \(Int(seconds)) seconds.")
            }
            guard let value = try await group.next() else {
                throw AIImageGenerationError.remote("请求超时", rawLog: "AI image API test task group returned no result.")
            }
            group.cancelAll()
            return value
        }
    }

    private static func renderPrompt(input: String, template: String) -> String {
        let fixedPrompt = AISkillSettingsStore.fixedPromptText(from: template)
        guard !fixedPrompt.isEmpty else {
            return input
        }
        // 用户只维护固定生成要求，快捷指令传入的文案由代码统一拼接。
        return "\(fixedPrompt)\n\(input)"
    }

    private static func galleryTitle(from prompt: String) -> String {
        let seed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = String(seed.prefix(16))
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return "AI 生图 \(prefix.isEmpty ? "" : "· \(prefix)") · \(formatter.string(from: Date()))"
    }
}

private enum PhotoLibrarySaver {
    static func save(_ image: UIImage) async throws {
        let status = await authorizationStatus()
        guard status == .authorized || status == .limited else {
            throw AIImageGenerationError.remote("没有系统相册写入权限", rawLog: "PHPhotoLibrary addOnly authorization denied: \(status.rawValue)")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                // 快捷指令开关开启时，将最终裁剪后的图片写入系统照片应用。
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: AIImageErrorParser.parse(error))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: AIImageGenerationError.remote("保存到系统相册失败", rawLog: "PHPhotoLibrary.performChanges returned success=false without error"))
                }
            }
        }
    }

    private static func authorizationStatus() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if current != .notDetermined {
            return current
        }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
