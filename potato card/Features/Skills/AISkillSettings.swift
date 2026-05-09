import AppIntents
import Combine
import CoreGraphics
import Foundation
import UIKit

struct AIImageModelOption: Identifiable, Hashable {
    let id: String
    let title: String
    let isCustom: Bool
}

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
            .doubaoSeedream: "豆包 Seedream"
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
            return "豆包 Seedream"
        }
    }

    var defaultModel: String {
        builtInModels.first?.id ?? ""
    }

    var builtInModels: [AIImageModelOption] {
        switch self {
        case .openAI:
            return [
                AIImageModelOption(id: "gpt-image-1", title: "gpt-image-1", isCustom: false)
            ]
        case .gemini:
            return [
                AIImageModelOption(id: "gemini-2.5-flash-image", title: "gemini-2.5-flash-image", isCustom: false)
            ]
        case .aliWanx:
            return [
                AIImageModelOption(id: "wanx2.1-t2i-turbo", title: "wanx2.1-t2i-turbo", isCustom: false)
            ]
        case .doubaoSeedream:
            return [
                AIImageModelOption(id: "doubao-seedream-4-0-250828", title: "Doubao-Seedream-4.0", isCustom: false)
            ]
        }
    }

    func builtInModelTitle(for modelID: String) -> String? {
        builtInModels.first(where: { $0.id == modelID })?.title
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

        static func customModelsKey(for provider: AIImageModelProvider) -> String {
            switch provider {
            case .openAI:
                return "openaiCustomModels"
            case .gemini:
                return "geminiCustomModels"
            case .aliWanx:
                return "aliWanxCustomModels"
            case .doubaoSeedream:
                return "doubaoCustomModels"
            }
        }
    }

    @Published private(set) var config: AISkillConfiguration
    @Published var apiKeyInput = ""
    @Published private(set) var apiKeyExists = false
    @Published private(set) var keyStatusText = "未配置 API Key"
    @Published private(set) var customModels: [String] = []
    @Published var toastMessage: String?

    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.config = Self.loadConfiguration(from: userDefaults)
        self.customModels = Self.loadCustomModels(for: config.provider, from: userDefaults)
        migrateSelectedModelIfNeeded()
        refreshAPIKeyState()
    }

    var availableModelOptions: [AIImageModelOption] {
        let customOptions = customModels.map {
            AIImageModelOption(id: $0, title: $0, isCustom: true)
        }
        return config.provider.builtInModels + customOptions
    }

    var selectedModelTitle: String {
        modelTitle(for: config.defaultModel)
    }

    func updateProvider(_ provider: AIImageModelProvider) {
        guard config.provider != provider else { return }
        config.provider = provider
        config.defaultModel = provider.defaultModel
        customModels = Self.loadCustomModels(for: provider, from: userDefaults)
        persistConfiguration()
        refreshAPIKeyState()
    }

    func selectModel(_ modelID: String) {
        let trimmedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelID.isEmpty else { return }
        config.defaultModel = trimmedModelID
        persistConfiguration()
    }

    func addCustomModel(_ value: String) {
        let modelID = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty else { return }

        if let builtInModelID = builtInModelID(matching: modelID) {
            config.defaultModel = builtInModelID
            persistConfiguration()
            toastMessage = "已切换到内置模型"
            return
        }

        if !containsCustomModel(modelID) {
            customModels.append(modelID)
            persistCustomModels()
        }
        config.defaultModel = modelID
        persistConfiguration()
        toastMessage = "自定义模型已添加"
    }

    func deleteCustomModel(_ modelID: String) {
        let trimmedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        customModels.removeAll { $0.caseInsensitiveCompare(trimmedModelID) == .orderedSame }
        if config.defaultModel.caseInsensitiveCompare(trimmedModelID) == .orderedSame {
            config.defaultModel = config.provider.defaultModel
            persistConfiguration()
        }
        persistCustomModels()
        toastMessage = "自定义模型已删除"
    }

    func clearCustomModels() {
        let removedModels = customModels
        customModels.removeAll()
        if removedModels.contains(where: { $0.caseInsensitiveCompare(config.defaultModel) == .orderedSame }) {
            config.defaultModel = config.provider.defaultModel
            persistConfiguration()
        }
        persistCustomModels()
        toastMessage = "自定义模型已清空"
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
        customModels = Self.loadCustomModels(for: config.provider, from: userDefaults)
        migrateSelectedModelIfNeeded()
        refreshAPIKeyState()
    }

    func modelTitle(for modelID: String) -> String {
        if let title = config.provider.builtInModelTitle(for: modelID) {
            return title
        }
        return modelID.isEmpty ? config.provider.defaultModel : modelID
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

    private func persistCustomModels() {
        userDefaults.set(customModels, forKey: Constants.customModelsKey(for: config.provider))
    }

    private func migrateSelectedModelIfNeeded() {
        let modelID = config.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if modelID.isEmpty {
            config.defaultModel = config.provider.defaultModel
            persistConfiguration()
            return
        }

        if let builtInModelID = builtInModelID(matching: modelID) {
            config.defaultModel = builtInModelID
            persistConfiguration()
            return
        }

        guard !containsCustomModel(modelID) else {
            return
        }

        // 兼容旧版本纯文本模型名，非内置模型自动纳入当前服务的自定义列表。
        customModels.append(modelID)
        persistCustomModels()
    }

    private func builtInModelID(matching modelIDOrTitle: String) -> String? {
        config.provider.builtInModels.first {
            $0.id.caseInsensitiveCompare(modelIDOrTitle) == .orderedSame ||
            $0.title.caseInsensitiveCompare(modelIDOrTitle) == .orderedSame
        }?.id
    }

    private func containsCustomModel(_ modelID: String) -> Bool {
        customModels.contains {
            $0.caseInsensitiveCompare(modelID) == .orderedSame
        }
    }

    nonisolated static func loadConfiguration(from userDefaults: UserDefaults = .standard) -> AISkillConfiguration {
        guard let data = userDefaults.data(forKey: Constants.configurationKey),
              var config = try? JSONDecoder().decode(AISkillConfiguration.self, from: data)
        else {
            return AISkillConfiguration()
        }
        config.promptTemplate = fixedPromptText(from: config.promptTemplate)
        if config.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config.defaultModel = config.provider.defaultModel
        }
        return config
    }

    nonisolated private static func loadCustomModels(for provider: AIImageModelProvider, from userDefaults: UserDefaults) -> [String] {
        let models = userDefaults.stringArray(forKey: Constants.customModelsKey(for: provider)) ?? []
        var seen = Set<String>()
        return models.compactMap { value in
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedValue.isEmpty else { return nil }
            let normalized = trimmedValue.lowercased()
            guard !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return trimmedValue
        }
    }

    nonisolated static func fixedPromptText(from value: String) -> String {
        value
            .replacingOccurrences(of: "{{input}}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
