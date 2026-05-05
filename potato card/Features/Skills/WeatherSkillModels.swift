import CoreLocation
import CoreGraphics
import Foundation

struct Skill: Identifiable, Equatable {
    let id: String
    let title: String
    let isEnabled: Bool
    let lastSyncAt: Date?
    let previewSummary: String
}

enum WeatherCityMode: String, Codable, CaseIterable, Identifiable {
    case automatic
    case fixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "当前位置"
        case .fixed:
            return "固定城市"
        }
    }
}

enum WeatherUpdateFrequency: String, Codable, CaseIterable, Identifiable {
    case hourly
    case everyThreeHours
    case daily

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hourly:
            return "每小时"
        case .everyThreeHours:
            return "每 3 小时"
        case .daily:
            return "每天"
        }
    }
}

enum WeatherDisplayTemplate: String, Codable, CaseIterable, Identifiable {
    case minimalist
    case blueMinimalist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimalist:
            return "白色版"
        case .blueMinimalist:
            return "蓝色版"
        }
    }
}

struct WeatherCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var qWeatherLocationQuery: String {
        String(format: "%.2f,%.2f", longitude, latitude)
    }
}

struct WeatherLocationOption: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let admin1: String
    let admin2: String
    let country: String
    let timezone: String
    let coordinate: WeatherCoordinate

    var displayName: String {
        let detailParts = [admin2, admin1, country].filter { !$0.trimmed.isEmpty }
        if detailParts.isEmpty {
            return name
        }

        return "\(name) · \(detailParts.joined(separator: " / "))"
    }
}

struct WeatherTargetDeviceSnapshot: Codable, Equatable {
    let id: String
    let name: String
    let address: String
    let pixelWidth: Int
    let pixelHeight: Int
    let colorMode: EInkColorMode
    let isFallback: Bool

    init(device: BleDevice) {
        id = device.id
        name = device.name
        address = device.address
        pixelWidth = Int(device.profile.pixelSize.width)
        pixelHeight = Int(device.profile.pixelSize.height)
        colorMode = device.profile.colorMode
        isFallback = device.profile.isFallback
    }

    var profile: EInkDeviceProfile {
        EInkDeviceProfile(
            name: name,
            pixelSize: CGSize(width: pixelWidth, height: pixelHeight),
            colorMode: colorMode,
            isFallback: isFallback
        )
    }
}

struct WeatherSkillConfiguration: Codable, Equatable {
    var isEnabled = true
    var apiKey = ""
    var apiHost = ""
    var cityMode: WeatherCityMode = .automatic
    var fixedCityQuery = "深圳"
    var fixedLocation: WeatherLocationOption?
    var latestCoordinate: WeatherCoordinate?
    var showsAirQuality = true
    var updateFrequency: WeatherUpdateFrequency = .hourly
    var template: WeatherDisplayTemplate = .minimalist
    var targetDeviceID = ""
    var targetDeviceSnapshot: WeatherTargetDeviceSnapshot?
    var lastSyncAt: Date?

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case apiKey
        case apiHost
        case cityMode
        case fixedCityQuery
        case fixedLocation
        case latestCoordinate
        case showsAirQuality
        case updateFrequency
        case template
        case targetDeviceID
        case targetDeviceSnapshot
        case lastSyncAt
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        // Host 和 Key 现在随技能配置保存在 UserDefaults，卸载重装后会被清空。
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        apiHost = try container.decodeIfPresent(String.self, forKey: .apiHost) ?? ""
        cityMode = try container.decodeIfPresent(WeatherCityMode.self, forKey: .cityMode) ?? .automatic
        fixedCityQuery = try container.decodeIfPresent(String.self, forKey: .fixedCityQuery) ?? "深圳"
        fixedLocation = try container.decodeIfPresent(WeatherLocationOption.self, forKey: .fixedLocation)
        latestCoordinate = try container.decodeIfPresent(WeatherCoordinate.self, forKey: .latestCoordinate)
        // 空气质量不再提供开关，旧配置即使保存过 false 也统一恢复为展示。
        showsAirQuality = true
        updateFrequency = try container.decodeIfPresent(WeatherUpdateFrequency.self, forKey: .updateFrequency) ?? .hourly
        if let templateRawValue = try container.decodeIfPresent(String.self, forKey: .template) {
            // 模板值需要向前兼容，未知模板回退到极简版，避免整份配置读取失败。
            template = WeatherDisplayTemplate(rawValue: templateRawValue) ?? .minimalist
        } else {
            template = .minimalist
        }
        targetDeviceID = try container.decodeIfPresent(String.self, forKey: .targetDeviceID) ?? ""
        targetDeviceSnapshot = try container.decodeIfPresent(WeatherTargetDeviceSnapshot.self, forKey: .targetDeviceSnapshot)
        lastSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        // 显式编码凭据配置，确保 App 更新时 UserDefaults 能继续保留。
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(apiHost, forKey: .apiHost)
        try container.encode(cityMode, forKey: .cityMode)
        try container.encode(fixedCityQuery, forKey: .fixedCityQuery)
        try container.encodeIfPresent(fixedLocation, forKey: .fixedLocation)
        try container.encodeIfPresent(latestCoordinate, forKey: .latestCoordinate)
        try container.encode(true, forKey: .showsAirQuality)
        try container.encode(updateFrequency, forKey: .updateFrequency)
        try container.encode(template, forKey: .template)
        try container.encode(targetDeviceID, forKey: .targetDeviceID)
        try container.encodeIfPresent(targetDeviceSnapshot, forKey: .targetDeviceSnapshot)
        try container.encodeIfPresent(lastSyncAt, forKey: .lastSyncAt)
    }
}

struct WeatherSkillSnapshot: Equatable {
    struct CurrentWeather: Equatable {
        let observedAt: Date
        let temperature: Int
        let feelsLike: Int
        let conditionText: String
        let iconCode: String
        let tempMax: Int?
        let tempMin: Int?
        let humidity: Int?
    }

    struct HourlyWeather: Equatable, Identifiable {
        let id = UUID()
        let date: Date
        let temperature: Int
        let conditionText: String
        let iconCode: String
    }

    struct AirQuality: Equatable {
        let aqiText: String
        let category: String
        let primaryPollutant: String
        let colorHex: String
    }

    let location: WeatherLocationOption
    let current: CurrentWeather
    let hourly: [HourlyWeather]
    let airQuality: AirQuality?
    let updatedAt: Date
}

enum WeatherSkillLoadState: Equatable {
    case idle
    case missingCredentials
    case locating
    case loading
    case loaded
    case failed(String)

    var message: String {
        switch self {
        case .idle:
            return "等待刷新"
        case .missingCredentials:
            return "请先填写和风天气 API Host 和 API Key"
        case .locating:
            return "正在获取当前位置"
        case .loading:
            return "正在获取天气数据"
        case .loaded:
            return "天气已更新"
        case .failed(let message):
            return message
        }
    }
}

enum WeatherSkillError: LocalizedError {
    case missingCredentials
    case invalidHost
    case missingCitySelection
    case locationDenied
    case locationUnavailable
    case remote(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "请先填写和风天气 API Host 和 API Key。"
        case .invalidHost:
            return "API Host 格式不正确，请输入控制台中的 Host。"
        case .missingCitySelection:
            return "请先选择一个固定城市。"
        case .locationDenied:
            return "定位权限不可用，请改用固定城市或在系统设置中开启定位。"
        case .locationUnavailable:
            return "当前位置暂时不可用，请稍后重试。"
        case .remote(let message):
            return message
        case .invalidResponse:
            return "天气服务返回了无法识别的数据。"
        }
    }
}

extension WeatherSkillSnapshot {
    var summaryText: String {
        "\(current.temperature)°C \(current.conditionText)"
    }
}

extension WeatherSkillConfiguration {
    var hasCredentials: Bool {
        !apiKey.trimmed.isEmpty && !apiHost.trimmed.isEmpty
    }
}

extension Skill {
    static func weather(summary: String, configuration: WeatherSkillConfiguration) -> Skill {
        Skill(
            id: "weather",
            title: "天气看板",
            isEnabled: configuration.isEnabled,
            lastSyncAt: configuration.lastSyncAt,
            previewSummary: summary
        )
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
