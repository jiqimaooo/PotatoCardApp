import Foundation
import UIKit

typealias AIImageDebugLogger = @MainActor (String) -> Void

struct AIImageGenerationRequest {
    let prompt: String
    let model: String
    let size: AIImageSize
    let apiKey: String
    let timeoutInterval: TimeInterval
    let debugLog: AIImageDebugLogger?
}

extension AIImageGenerationRequest {
    nonisolated func writeDebugLog(_ message: String) async {
        await debugLog?(message)
    }
}

protocol AIImageProvider {
    nonisolated func generateImageData(request: AIImageGenerationRequest) async throws -> Data
}

enum AIImageGenerationError: LocalizedError {
    case missingPrompt
    case missingAPIKey(String)
    case invalidResponse
    case invalidImageData
    case keychain(String)
    case remote(String, rawLog: String? = nil)

    nonisolated var errorDescription: String? {
        switch self {
        case .missingPrompt:
            return "Prompt 不能为空。"
        case .missingAPIKey(let provider):
            return "请先在 AI 生图设置里配置 \(provider) 的 API Key。"
        case .invalidResponse:
            return "图片生成接口返回格式不正确。"
        case .invalidImageData:
            return "图片生成成功但图片数据无法解析。"
        case .keychain(let message):
            return message
        case .remote(let message, _):
            return message
        }
    }
}

enum AIImageProviderFactory {
    nonisolated static func provider(for kind: AIImageModelProvider) -> AIImageProvider {
        switch kind {
        case .openAI:
            return OpenAIImageProvider()
        case .gemini:
            return GeminiImageProvider()
        case .aliWanx:
            return AliWanxImageProvider()
        case .doubaoSeedream:
            return DoubaoSeedreamImageProvider()
        }
    }
}

struct OpenAIImageProvider: AIImageProvider {
    nonisolated func generateImageData(request: AIImageGenerationRequest) async throws -> Data {
        await request.writeDebugLog("OpenAI: 准备图片生成请求，model=\(request.model), size=\(request.size.openAIRequestSize)")
        let body: [String: Any] = [
            "model": request.model,
            "prompt": request.prompt,
            "size": request.size.openAIRequestSize,
            "n": 1,
            "output_format": "png"
        ]

        let data = try await AIImageHTTPClient.postJSON(
            url: URL(string: "https://api.openai.com/v1/images/generations")!,
            headers: ["Authorization": "Bearer \(request.apiKey)"],
            body: body,
            timeoutInterval: request.timeoutInterval,
            debugLog: request.debugLog
        )
        await request.writeDebugLog("OpenAI: 已收到响应，开始解析图片数据")
        return try AIImageResponseParser.decodeOpenAIImageData(data)
    }
}

struct GeminiImageProvider: AIImageProvider {
    nonisolated func generateImageData(request: AIImageGenerationRequest) async throws -> Data {
        let encodedModel = request.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? request.model
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent")!
        await request.writeDebugLog("Gemini: 准备图片生成请求，model=\(request.model)")
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": request.prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "responseModalities": ["TEXT", "IMAGE"]
            ]
        ]

        let data = try await AIImageHTTPClient.postJSON(
            url: url,
            headers: ["x-goog-api-key": request.apiKey],
            body: body,
            timeoutInterval: request.timeoutInterval,
            debugLog: request.debugLog
        )
        await request.writeDebugLog("Gemini: 已收到响应，开始解析图片数据")
        return try AIImageResponseParser.decodeGeminiImageData(data)
    }
}

struct AliWanxImageProvider: AIImageProvider {
    nonisolated func generateImageData(request: AIImageGenerationRequest) async throws -> Data {
        await request.writeDebugLog("通义万相: 准备异步图片生成任务，model=\(request.model), size=\(request.size.dashScopeRequestSize)")
        let body: [String: Any] = [
            "model": request.model,
            "input": [
                "prompt": request.prompt
            ],
            "parameters": [
                "size": request.size.dashScopeRequestSize,
                "n": 1
            ]
        ]
        let endpoint = URL(string: "https://dashscope.aliyuncs.com/api/v1/services/aigc/text2image/image-synthesis")!
        let submitData = try await AIImageHTTPClient.postJSON(
            url: endpoint,
            headers: [
                "Authorization": "Bearer \(request.apiKey)",
                "X-DashScope-Async": "enable"
            ],
            body: body,
            timeoutInterval: request.timeoutInterval,
            debugLog: request.debugLog
        )
        let taskID = try AIImageResponseParser.decodeDashScopeTaskID(submitData)
        await request.writeDebugLog("通义万相: 任务已提交，task_id=\(taskID)")
        let imageURL = try await pollTask(taskID: taskID, apiKey: request.apiKey, debugLog: request.debugLog)
        await request.writeDebugLog("通义万相: 图片已生成，开始下载结果")
        return try await AIImageHTTPClient.download(url: imageURL, debugLog: request.debugLog)
    }

    nonisolated private func pollTask(taskID: String, apiKey: String, debugLog: AIImageDebugLogger?) async throws -> URL {
        let endpoint = URL(string: "https://dashscope.aliyuncs.com/api/v1/tasks/\(taskID)")!
        for index in 0..<36 {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            await debugLog?("通义万相: 第 \(index + 1) 次查询任务状态")
            let data = try await AIImageHTTPClient.get(
                url: endpoint,
                headers: ["Authorization": "Bearer \(apiKey)"],
                timeoutInterval: 20,
                debugLog: debugLog
            )
            if let result = try AIImageResponseParser.decodeDashScopeTaskResult(data) {
                await debugLog?("通义万相: 任务状态 SUCCEEDED")
                return result
            }
        }
        throw AIImageGenerationError.remote("请求超时", rawLog: "DashScope task polling timed out after 72 seconds. task_id=\(taskID)")
    }
}

struct DoubaoSeedreamImageProvider: AIImageProvider {
    nonisolated func generateImageData(request: AIImageGenerationRequest) async throws -> Data {
        let model = normalizedModel(request.model)
        await request.writeDebugLog("豆包 Seedream: 准备图片生成请求，model=\(model)")
        let body: [String: Any] = [
            "model": model,
            "prompt": request.prompt,
            "size": "2K",
            "sequential_image_generation": "disabled",
            "stream": false,
            "response_format": "url",
            "watermark": false
        ]

        let data = try await AIImageHTTPClient.postJSON(
            url: URL(string: "https://ark.cn-beijing.volces.com/api/v3/images/generations")!,
            headers: ["Authorization": "Bearer \(request.apiKey)"],
            body: body,
            timeoutInterval: request.timeoutInterval,
            debugLog: request.debugLog
        )
        await request.writeDebugLog("豆包 Seedream: 已收到响应，开始解析图片数据")
        return try AIImageResponseParser.decodeOpenAIImageData(data)
    }

    nonisolated private func normalizedModel(_ model: String) -> String {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "doubao-seedream-4.0", "doubao-seedream-4-0", "doubao-seedream-4":
            return "doubao-seedream-4-0-250828"
        default:
            return model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "doubao-seedream-4-0-250828"
                : model
        }
    }
}

private enum AIImageHTTPClient {
    nonisolated static func postJSON(url: URL, headers: [String: String], body: [String: Any], timeoutInterval: TimeInterval, debugLog: AIImageDebugLogger? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeoutInterval
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request, debugLog: debugLog)
    }

    nonisolated static func get(url: URL, headers: [String: String], timeoutInterval: TimeInterval = 60, debugLog: AIImageDebugLogger? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutInterval
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        return try await perform(request, debugLog: debugLog)
    }

    nonisolated static func download(url: URL, debugLog: AIImageDebugLogger? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        return try await perform(request, debugLog: debugLog)
    }

    nonisolated private static func perform(_ request: URLRequest, debugLog: AIImageDebugLogger?) async throws -> Data {
        await debugLog?("HTTP: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "-")")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            await debugLog?("HTTP: 请求失败 \(error.localizedDescription)")
            throw AIImageErrorParser.parse(error)
        }
        guard let http = response as? HTTPURLResponse else {
            await debugLog?("HTTP: 响应不是 HTTPURLResponse")
            throw AIImageGenerationError.invalidResponse
        }
        await debugLog?("HTTP: status=\(http.statusCode), bytes=\(data.count)")
        guard (200..<300).contains(http.statusCode) else {
            throw AIImageErrorParser.parseHTTP(statusCode: http.statusCode, data: data, url: request.url)
        }
        return data
    }
}

private enum AIImageResponseParser {
    nonisolated static func decodeOpenAIImageData(_ data: Data) throws -> Data {
        let response: OpenAIImageResponse
        do {
            response = try JSONDecoder().decode(OpenAIImageResponse.self, from: data)
        } catch {
            throw AIImageErrorParser.parseResponseDecodeError(error, data: data, context: "OpenAI image response decode failed")
        }
        guard let item = response.data.first else { throw AIImageGenerationError.invalidResponse }
        if let b64 = item.b64Json, let imageData = Data(base64Encoded: b64) {
            return imageData
        }
        if let urlString = item.url, let url = URL(string: urlString) {
            do {
                return try Data(contentsOf: url)
            } catch {
                throw AIImageErrorParser.parse(error)
            }
        }
        throw AIImageGenerationError.invalidResponse
    }

    nonisolated static func decodeGeminiImageData(_ data: Data) throws -> Data {
        let response: GeminiImageResponse
        do {
            response = try JSONDecoder().decode(GeminiImageResponse.self, from: data)
        } catch {
            throw AIImageErrorParser.parseResponseDecodeError(error, data: data, context: "Gemini image response decode failed")
        }
        let parts = response.candidates?.first?.content.parts ?? []
        for part in parts {
            if let b64 = part.inlineData?.data, let imageData = Data(base64Encoded: b64) {
                return imageData
            }
        }
        throw AIImageGenerationError.invalidResponse
    }

    nonisolated static func decodeDashScopeTaskID(_ data: Data) throws -> String {
        let response: DashScopeSubmitResponse
        do {
            response = try JSONDecoder().decode(DashScopeSubmitResponse.self, from: data)
        } catch {
            throw AIImageErrorParser.parseResponseDecodeError(error, data: data, context: "DashScope submit response decode failed")
        }
        guard let taskID = response.output.taskID, !taskID.isEmpty else {
            throw AIImageGenerationError.invalidResponse
        }
        return taskID
    }

    nonisolated static func decodeDashScopeTaskResult(_ data: Data) throws -> URL? {
        let response: DashScopeTaskResponse
        do {
            response = try JSONDecoder().decode(DashScopeTaskResponse.self, from: data)
        } catch {
            throw AIImageErrorParser.parseResponseDecodeError(error, data: data, context: "DashScope task response decode failed")
        }
        switch response.output.taskStatus {
        case "SUCCEEDED":
            guard let urlString = response.output.results?.first?.url,
                  let url = URL(string: urlString)
            else {
                throw AIImageGenerationError.invalidResponse
            }
            return url
        case "FAILED", "CANCELED", "UNKNOWN":
            throw AIImageGenerationError.remote(
                response.output.message ?? "通义万相生成失败。",
                rawLog: String(data: data, encoding: .utf8) ?? "DashScope task failed with non-utf8 body"
            )
        default:
            return nil
        }
    }

    nonisolated static func decodeFlexibleImageData(_ data: Data) throws -> Data {
        if let response = try? JSONDecoder().decode(OpenAIImageResponse.self, from: data),
           let item = response.data.first {
            if let b64 = item.b64Json, let imageData = Data(base64Encoded: b64) {
                return imageData
            }
            if let urlString = item.url, let url = URL(string: urlString) {
                do {
                    return try Data(contentsOf: url)
                } catch {
                    throw AIImageErrorParser.parse(error)
                }
            }
        }
        if UIImageDataProbe.isImage(data) {
            return data
        }
        throw AIImageGenerationError.invalidResponse
    }
}

private struct OpenAIImageResponse: Decodable {
    struct Item: Decodable {
        let b64Json: String?
        let url: String?

        private enum CodingKeys: String, CodingKey {
            case b64Json = "b64_json"
            case url
        }
    }

    let data: [Item]
}

private struct GeminiImageResponse: Decodable {
    struct Candidate: Decodable {
        let content: Content
    }

    struct Content: Decodable {
        let parts: [Part]
    }

    struct Part: Decodable {
        let inlineData: InlineData?
    }

    struct InlineData: Decodable {
        let data: String
    }

    let candidates: [Candidate]?
}

private struct DashScopeSubmitResponse: Decodable {
    struct Output: Decodable {
        let taskID: String?

        private enum CodingKeys: String, CodingKey {
            case taskID = "task_id"
        }
    }

    let output: Output
}

private struct DashScopeTaskResponse: Decodable {
    struct Output: Decodable {
        struct Result: Decodable {
            let url: String?
        }

        let taskStatus: String
        let results: [Result]?
        let message: String?

        private enum CodingKeys: String, CodingKey {
            case taskStatus = "task_status"
            case results
            case message
        }
    }

    let output: Output
}

private enum UIImageDataProbe {
    nonisolated static func isImage(_ data: Data) -> Bool {
        data.starts(with: [0x89, 0x50, 0x4E, 0x47]) || data.starts(with: [0xFF, 0xD8, 0xFF])
    }
}

private extension AIImageSize {
    var openAIRequestSize: String {
        if width > height {
            return "1536x1024"
        }
        if height > width {
            return "1024x1536"
        }
        return "1024x1024"
    }

    var dashScopeRequestSize: String {
        if width > height {
            return "1536*1024"
        }
        if height > width {
            return "1024*1536"
        }
        return "1024*1024"
    }
}
