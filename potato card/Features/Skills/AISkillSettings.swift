import AppIntents
import Combine
import CoreGraphics
import Foundation
import UIKit

enum AIImageModelProvider: String, Codable, CaseIterable, Identifiable, AppEnum {
    case openAI
    case gemini
    case aliWanx
    case doubaoSeedream

    var id: String { rawValue }

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "模型服务")

    static var caseDisplayRepresentations: [AIImageModelProvider: DisplayRepresentation] {
        [
            .openAI: "OpenAI",
            .gemini: "Gemini",
            .aliWanx: "阿里通义千问 / 通义万相",
            .doubaoSeedream: "豆包 Seedream 4.0"
        ]
    }

    var title: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .gemini:
            return "Gemini"
        case .aliWanx:
            return "阿里通义千问 / 通义万相"
        case .doubaoSeedream:
            return "豆包 Seedream 4.0"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI:
            return "gpt-image-1"
        case .gemini:
            return "gemini-2.5-flash-image"
        case .aliWanx:
            return "wanx2.1-t2i-turbo"
        case .doubaoSeedream:
            return "doubao-seedream-4-0-250828"
        }
    }

    var keychainKey: String {
        "aiImage.apiKey.\(rawValue)"
    }
}

struct AIImageSize: Codable, Equatable, Hashable {
    var width: Int
    var height: Int

    static let `default` = AIImageSize(width: 400, height: 600)
    static let supportedDefaults = [AIImageSize.default]

    var cgSize: CGSize {
        CGSize(width: width, height: height)
    }

    var displayText: String {
        "\(width)×\(height)"
    }

    var starSeparatedText: String {
        "\(width)*\(height)"
    }

    static func parse(_ value: String?) -> AIImageSize? {
        guard let value else { return nil }
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: "*", with: "x")
            .replacingOccurrences(of: " ", with: "")
        let parts = normalized.split(separator: "x")
        guard parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1]),
              width > 0,
              height > 0
        else {
            return nil
        }
        return AIImageSize(width: width, height: height)
    }
}

struct AISkillConfiguration: Codable, Equatable {
    var provider: AIImageModelProvider = .openAI
    var defaultModel = AIImageModelProvider.openAI.defaultModel
    var defaultSize = AIImageSize.default
    var promptTemplate = "适合六色墨水屏显示，简洁构图，高对比度，竖版海报风格。"
    var autoTransferToDevice = false
}

@MainActor
final class AISkillSettingsStore: ObservableObject {
    private enum Constants {
        static let configurationKey = "aiImageSkillConfiguration"
    }

    @Published private(set) var config: AISkillConfiguration
    @Published var apiKeyInput = ""
    @Published private(set) var apiKeyExists = false
    @Published private(set) var keyStatusText = "未配置 API Key"
    @Published var toastMessage: String?

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.config = Self.loadConfiguration(from: userDefaults)
        refreshAPIKeyState()
    }

    func updateProvider(_ provider: AIImageModelProvider) {
        guard config.provider != provider else { return }
        config.provider = provider
        config.defaultModel = provider.defaultModel
        persistConfiguration()
        refreshAPIKeyState()
    }

    func updateDefaultModel(_ value: String) {
        config.defaultModel = value.trimmingCharacters(in: .whitespacesAndNewlines)
        persistConfiguration()
    }

    func updateDefaultSize(width: String, height: String) {
        guard let width = Int(width), let height = Int(height), width > 0, height > 0 else { return }
        config.defaultSize = AIImageSize(width: width, height: height)
        persistConfiguration()
    }

    func updateDefaultSize(_ size: AIImageSize) {
        config.defaultSize = size
        persistConfiguration()
    }

    func updatePromptTemplate(_ value: String) {
        config.promptTemplate = Self.fixedPromptText(from: value)
        persistConfiguration()
    }

    func updateAutoTransferToDevice(_ value: Bool) {
        config.autoTransferToDevice = value
        persistConfiguration()
    }

    func updateAPIKey(_ value: String) {
        apiKeyInput = value
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try KeychainService.delete(key: config.provider.keychainKey)
            } else {
                try KeychainService.save(trimmed, key: config.provider.keychainKey)
            }
        } catch {
            toastMessage = error.localizedDescription
        }
        refreshAPIKeyState(loadValue: false)
    }

    func clearAPIKey() {
        do {
            try KeychainService.delete(key: config.provider.keychainKey)
            apiKeyInput = ""
            refreshAPIKeyState(loadValue: false)
            toastMessage = "API Key 已清空"
        } catch {
            toastMessage = error.localizedDescription
        }
    }

    func reload() {
        config = Self.loadConfiguration(from: userDefaults)
        refreshAPIKeyState()
    }

    func refreshAPIKeyState(loadValue: Bool = true) {
        let key = config.provider.keychainKey
        apiKeyExists = KeychainService.exists(key: key)
        keyStatusText = apiKeyExists ? "已保存 API Key" : "未配置 API Key"
        if loadValue {
            apiKeyInput = (try? KeychainService.read(key: key)) ?? ""
        }
    }

    private func persistConfiguration() {
        guard let data = try? encoder.encode(config) else { return }
        userDefaults.set(data, forKey: Constants.configurationKey)
    }

    nonisolated static func loadConfiguration(from userDefaults: UserDefaults = .standard) -> AISkillConfiguration {
        guard let data = userDefaults.data(forKey: Constants.configurationKey),
              var config = try? JSONDecoder().decode(AISkillConfiguration.self, from: data)
        else {
            return AISkillConfiguration()
        }
        config.promptTemplate = fixedPromptText(from: config.promptTemplate)
        return config
    }

    nonisolated static func fixedPromptText(from value: String) -> String {
        value
            .replacingOccurrences(of: "{{input}}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
