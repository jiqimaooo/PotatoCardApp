import Foundation

struct AIImageParsedError: LocalizedError, Equatable {
    let message: String
    let suggestion: String
    let rawLog: String

    var errorDescription: String? {
        message
    }

    var recoverySuggestion: String? {
        suggestion
    }
}

enum AIImageErrorParser {
    static func parse(_ error: Error, provider: AIImageModelProvider? = nil) -> AIImageParsedError {
        if let parsed = error as? AIImageParsedError {
            return parsed
        }
        if let generationError = error as? AIImageGenerationError {
            return parseGenerationError(generationError, provider: provider)
        }
        if let urlError = error as? URLError {
            return parseURLError(urlError)
        }

        let rawLog = String(describing: error)
        let lowercased = rawLog.lowercased()
        return parseRawLog(lowercased, rawLog: rawLog, fallbackMessage: "服务返回异常")
    }

    static func parseHTTP(statusCode: Int, data: Data, url: URL?) -> AIImageParsedError {
        let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body, \(data.count) bytes>"
        let rawLog = """
        HTTP \(statusCode)
        URL: \(url?.absoluteString ?? "-")
        Body:
        \(body)
        """
        return parseRawLog(body.lowercased(), rawLog: rawLog, statusCode: statusCode, fallbackMessage: "服务返回异常")
    }

    static func parseResponseDecodeError(_ error: Error, data: Data, context: String) -> AIImageParsedError {
        let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body, \(data.count) bytes>"
        let rawLog = """
        \(context)
        Decode error: \(String(describing: error))
        Body:
        \(body)
        """
        return parseRawLog(body.lowercased(), rawLog: rawLog, fallbackMessage: "服务返回异常")
    }

    private static func parseGenerationError(_ error: AIImageGenerationError, provider: AIImageModelProvider?) -> AIImageParsedError {
        switch error {
        case .missingPrompt:
            return AIImageParsedError(message: "Prompt 不能为空", suggestion: "请输入一段用于生成图片的描述。", rawLog: "missingPrompt")
        case .missingAPIKey(let providerName):
            return AIImageParsedError(message: "未配置 API Key", suggestion: "请先配置 \(providerName) 的 API Key。", rawLog: "missingAPIKey provider=\(providerName)")
        case .invalidResponse:
            return AIImageParsedError(message: "服务返回异常", suggestion: "接口返回格式无法识别，请检查模型名称或稍后重试。", rawLog: "invalidResponse provider=\(provider?.rawValue ?? "-")")
        case .invalidImageData:
            return AIImageParsedError(message: "图片数据无法解析", suggestion: "服务没有返回可用图片，请检查模型是否支持图片生成。", rawLog: "invalidImageData provider=\(provider?.rawValue ?? "-")")
        case .keychain(let message):
            return AIImageParsedError(message: "Keychain 访问失败", suggestion: "请重试，或重新保存 API Key。", rawLog: message)
        case .remote(let message, let rawLog):
            return parseRawLog((rawLog ?? message).lowercased(), rawLog: rawLog ?? message, fallbackMessage: message)
        }
    }

    private static func parseURLError(_ error: URLError) -> AIImageParsedError {
        switch error.code {
        case .timedOut:
            return AIImageParsedError(message: "请求超时", suggestion: "请稍后重试，或检查当前网络是否稳定。", rawLog: "URLError timedOut: \(error)")
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return AIImageParsedError(message: "网络连接失败", suggestion: "请检查网络连接、代理或模型服务地址。", rawLog: "URLError network: \(error)")
        default:
            return AIImageParsedError(message: "网络异常", suggestion: "请稍后重试，或切换网络后再试。", rawLog: "URLError \(error.code.rawValue): \(error)")
        }
    }

    private static func parseRawLog(_ lowercased: String, rawLog: String, statusCode: Int? = nil, fallbackMessage: String) -> AIImageParsedError {
        if statusCode == 429 || lowercased.contains("resource_exhausted") || lowercased.contains("quota") || lowercased.contains("rate limit") {
            return AIImageParsedError(message: "配额不足", suggestion: "请检查账号余额、调用额度或稍后再试。", rawLog: rawLog)
        }
        if statusCode == 401 || statusCode == 403 || lowercased.contains("unauthorized") || lowercased.contains("permission denied") || lowercased.contains("invalid api key") {
            return AIImageParsedError(message: "API Key 无效或无权限", suggestion: "请确认 API Key 是否正确，并检查该 Key 是否有当前模型权限。", rawLog: rawLog)
        }
        if statusCode == 404 || lowercased.contains("model not found") || lowercased.contains("not found") {
            return AIImageParsedError(message: "模型不存在或不可用", suggestion: "请检查模型名称是否正确，或切换到该服务支持的图片模型。", rawLog: rawLog)
        }
        if lowercased.contains("safety") || lowercased.contains("blocked") || lowercased.contains("content policy") {
            return AIImageParsedError(message: "内容被安全策略拦截", suggestion: "请调整 Prompt，避免敏感、违规或受限内容。", rawLog: rawLog)
        }
        if lowercased.contains("timeout") || lowercased.contains("timed out") {
            return AIImageParsedError(message: "请求超时", suggestion: "请稍后重试，或检查当前网络是否稳定。", rawLog: rawLog)
        }
        if lowercased.contains("network") || lowercased.contains("cannot connect") || lowercased.contains("dns") {
            return AIImageParsedError(message: "网络异常", suggestion: "请检查网络连接、代理或模型服务地址。", rawLog: rawLog)
        }
        return AIImageParsedError(message: fallbackMessage, suggestion: "请检查模型服务、模型名称和 API Key，必要时复制详细日志排查。", rawLog: rawLog)
    }
}
