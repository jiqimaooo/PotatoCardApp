import Combine
import CoreLocation
import Foundation

@MainActor
final class WeatherSkillStore: ObservableObject {
    private enum Constants {
        static let configurationKey = "weatherSkillConfiguration"
    }

    @Published private(set) var config: WeatherSkillConfiguration
    @Published private(set) var snapshot: WeatherSkillSnapshot?
    @Published private(set) var loadState: WeatherSkillLoadState = .idle
    @Published private(set) var cityResults: [WeatherLocationOption] = []
    @Published private(set) var isSearchingCities = false
    @Published private(set) var locationStatusText = "未获取位置"

    private let locationProvider = WeatherSkillLocationProvider()
    private let service = WeatherSkillService()
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.config = Self.loadConfiguration(decoder: JSONDecoder(), userDefaults: userDefaults)
    }

    var skill: Skill {
        let summary = snapshot?.summaryText ?? "显示天气、空气质量和未来预报"
        return .weather(summary: summary, configuration: config)
    }

    func onAppear() async {
        guard snapshot == nil else { return }
        if config.hasCredentials {
            await refreshWeather()
        } else {
            loadState = .missingCredentials
        }
    }

    func updateEnabled(_ isEnabled: Bool) {
        config.isEnabled = isEnabled
        persistConfiguration()
    }

    func updateAPIKey(_ value: String) {
        let trimmedValue = value.trimmed
        config.apiKey = trimmedValue
        // API Key 跟随天气技能配置写入 UserDefaults，卸载 App 后会被系统清空。
        persistConfiguration()
        loadState = config.hasCredentials ? .idle : .missingCredentials
    }

    func updateAPIHost(_ value: String) {
        let trimmedValue = value.trimmed
        config.apiHost = trimmedValue
        // API Host 不再写入 Keychain，避免卸载重装后旧配置被自动恢复。
        persistConfiguration()
        loadState = config.hasCredentials ? .idle : .missingCredentials
    }

    func updateCityMode(_ mode: WeatherCityMode) {
        config.cityMode = mode
        persistConfiguration()
    }

    func updateFixedCityQuery(_ value: String) {
        config.fixedCityQuery = value
        persistConfiguration()
    }

    func updateFrequency(_ frequency: WeatherUpdateFrequency) {
        config.updateFrequency = frequency
        persistConfiguration()
    }

    func updateTemplate(_ template: WeatherDisplayTemplate) {
        config.template = template
        persistConfiguration()
    }

    func updateTargetDeviceID(_ deviceID: String) {
        config.targetDeviceID = deviceID
        if config.targetDeviceSnapshot?.id != deviceID {
            config.targetDeviceSnapshot = nil
        }
        persistConfiguration()
    }

    func updateTargetDevice(_ device: BleDevice) {
        config.targetDeviceID = device.id
        config.targetDeviceSnapshot = device.targetSnapshot
        persistConfiguration()
    }

    func updateTargetDeviceSnapshot(_ snapshot: WeatherTargetDeviceSnapshot) {
        config.targetDeviceID = snapshot.id
        config.targetDeviceSnapshot = snapshot
        persistConfiguration()
    }

    func searchCities(query: String? = nil) async {
        let trimmedQuery = (query ?? config.fixedCityQuery).trimmed
        guard !trimmedQuery.isEmpty else {
            cityResults = []
            return
        }

        guard config.hasCredentials else {
            loadState = .missingCredentials
            return
        }

        isSearchingCities = true
        defer { isSearchingCities = false }

        do {
            cityResults = try await service.lookupCities(
                query: trimmedQuery,
                credentials: credentials
            )
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func selectFixedCity(_ city: WeatherLocationOption) {
        config.fixedLocation = city
        config.fixedCityQuery = city.name
        cityResults = []
        persistConfiguration()
    }

    func refreshWeather() async {
        guard config.isEnabled else {
            loadState = .idle
            return
        }

        guard config.hasCredentials else {
            snapshot = nil
            loadState = .missingCredentials
            return
        }

        do {
            let resolvedLocation = try await resolveLocation()
            loadState = .loading
            snapshot = try await service.fetchWeatherSnapshot(
                for: resolvedLocation,
                includesAirQuality: true,
                credentials: credentials
            )
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func markSynced() {
        config.lastSyncAt = Date()
        persistConfiguration()
    }

    var hasCredentials: Bool {
        config.hasCredentials
    }

    private var credentials: WeatherSkillService.Credentials {
        WeatherSkillService.Credentials(
            apiHost: config.apiHost.trimmed,
            apiKey: config.apiKey.trimmed
        )
    }

    private func resolveLocation() async throws -> WeatherLocationOption {
        switch config.cityMode {
        case .automatic:
            loadState = .locating
            let coordinate = try await locationProvider.requestLocation()
            locationStatusText = "当前位置已更新"
            config.latestCoordinate = WeatherCoordinate(coordinate)
            persistConfiguration()
            return try await service.reverseLookupCity(
                coordinate: WeatherCoordinate(coordinate),
                credentials: credentials
            )
        case .fixed:
            if let fixedLocation = config.fixedLocation {
                locationStatusText = fixedLocation.displayName
                return fixedLocation
            }

            let query = config.fixedCityQuery.trimmed
            guard !query.isEmpty else {
                throw WeatherSkillError.missingCitySelection
            }

            let cities = try await service.lookupCities(query: query, credentials: credentials)
            guard let firstCity = cities.first else {
                throw WeatherSkillError.remote("没有找到匹配的城市，请换个关键词。")
            }

            selectFixedCity(firstCity)
            locationStatusText = firstCity.displayName
            return firstCity
        }
    }

    private func persistConfiguration() {
        guard let data = try? encoder.encode(config) else { return }
        userDefaults.set(data, forKey: Constants.configurationKey)
    }

    private static func loadConfiguration(decoder: JSONDecoder, userDefaults: UserDefaults) -> WeatherSkillConfiguration {
        guard
            let data = userDefaults.data(forKey: Constants.configurationKey),
            let configuration = try? decoder.decode(WeatherSkillConfiguration.self, from: data)
        else {
            return WeatherSkillConfiguration()
        }

        return configuration
    }
}

@MainActor
final class WeatherSkillLocationProvider: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<Void, Error>?
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() async throws -> CLLocationCoordinate2D {
        try await ensureAuthorized()

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private func ensureAuthorized() async throws {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return
        case .notDetermined:
            try await withCheckedThrowingContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        case .restricted, .denied:
            throw WeatherSkillError.locationDenied
        @unknown default:
            throw WeatherSkillError.locationUnavailable
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let authorizationContinuation else { return }

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            authorizationContinuation.resume()
            self.authorizationContinuation = nil
        case .restricted, .denied:
            authorizationContinuation.resume(throwing: WeatherSkillError.locationDenied)
            self.authorizationContinuation = nil
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: WeatherSkillError.locationUnavailable)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.first?.coordinate else {
            locationContinuation?.resume(throwing: WeatherSkillError.locationUnavailable)
            locationContinuation = nil
            return
        }

        locationContinuation?.resume(returning: coordinate)
        locationContinuation = nil
    }
}

actor WeatherSkillService {
    struct Credentials {
        let apiHost: String
        let apiKey: String
    }

    func lookupCities(query: String, credentials: Credentials) async throws -> [WeatherLocationOption] {
        let response: GeoLookupResponse = try await request(
            credentials: credentials,
            path: "/geo/v2/city/lookup",
            queryItems: [
                URLQueryItem(name: "location", value: query),
                URLQueryItem(name: "number", value: "8"),
                URLQueryItem(name: "lang", value: "zh")
            ]
        )

        guard response.code == "200" else {
            throw WeatherSkillError.remote(Self.message(for: response.code))
        }

        return response.location.map {
            WeatherLocationOption(
                id: $0.id,
                name: $0.name,
                admin1: $0.adm1,
                admin2: $0.adm2,
                country: $0.country,
                timezone: $0.tz,
                coordinate: WeatherCoordinate(latitude: Double($0.lat) ?? 0, longitude: Double($0.lon) ?? 0)
            )
        }
    }

    func reverseLookupCity(coordinate: WeatherCoordinate, credentials: Credentials) async throws -> WeatherLocationOption {
        let cities = try await lookupCities(query: coordinate.qWeatherLocationQuery, credentials: credentials)
        guard let city = cities.first else {
            throw WeatherSkillError.locationUnavailable
        }

        return city
    }

    func fetchWeatherSnapshot(
        for location: WeatherLocationOption,
        includesAirQuality: Bool,
        credentials: Credentials
    ) async throws -> WeatherSkillSnapshot {
        async let nowResponse: WeatherNowResponse = request(
            credentials: credentials,
            path: "/v7/weather/now",
            queryItems: [
                URLQueryItem(name: "location", value: location.id),
                URLQueryItem(name: "lang", value: "zh"),
                URLQueryItem(name: "unit", value: "m")
            ]
        )

        async let hourlyResponse: WeatherHourlyResponse = request(
            credentials: credentials,
            path: "/v7/weather/24h",
            queryItems: [
                URLQueryItem(name: "location", value: location.id),
                URLQueryItem(name: "lang", value: "zh"),
                URLQueryItem(name: "unit", value: "m")
            ]
        )

        // 每日预报只用于最高/最低温，失败时不影响天气主数据展示。
        async let dailyResponse: WeatherDailyResponse? = requestOptional(
            credentials: credentials,
            path: "/v7/weather/3d",
            queryItems: [
                URLQueryItem(name: "location", value: location.id),
                URLQueryItem(name: "lang", value: "zh"),
                URLQueryItem(name: "unit", value: "m")
            ]
        )

        async let airQualityResponse: AirQualityResponse? = includesAirQuality
            ? request(
                credentials: credentials,
                path: "/airquality/v1/current/\(Self.pathValue(location.coordinate.latitude))/\(Self.pathValue(location.coordinate.longitude))",
                queryItems: [URLQueryItem(name: "lang", value: "zh")]
            )
            : nil

        let now = try await nowResponse
        let hourly = try await hourlyResponse
        let daily = await dailyResponse
        let airQuality = try await airQualityResponse

        guard now.code == "200", let current = now.now else {
            throw WeatherSkillError.remote(Self.message(for: now.code))
        }

        guard hourly.code == "200" else {
            throw WeatherSkillError.remote(Self.message(for: hourly.code))
        }

        let updatedAt = Self.parseDate(now.updateTime) ?? Date()
        let todayForecast = daily?.code == "200" ? daily?.daily.first : nil
        let currentWeather = WeatherSkillSnapshot.CurrentWeather(
            observedAt: Self.parseDate(current.obsTime) ?? updatedAt,
            temperature: Int(current.temp) ?? 0,
            feelsLike: Int(current.feelsLike) ?? Int(current.temp) ?? 0,
            conditionText: current.text,
            iconCode: current.icon,
            tempMax: todayForecast.flatMap { Int($0.tempMax) },
            tempMin: todayForecast.flatMap { Int($0.tempMin) },
            humidity: Int(current.humidity)
        )

        // 保留接口返回的完整小时预报，具体取未来哪四个整点交给渲染层按当前时间判断。
        let hourlyWeather = hourly.hourly
            .compactMap { item -> WeatherSkillSnapshot.HourlyWeather? in
                guard let date = Self.parseDate(item.fxTime) else { return nil }
                return WeatherSkillSnapshot.HourlyWeather(
                    date: date,
                    temperature: Int(item.temp) ?? 0,
                    conditionText: item.text,
                    iconCode: item.icon
                )
            }
            .sorted { $0.date < $1.date }

        let airQualitySummary = airQuality?.indexes.first.map { index in
            WeatherSkillSnapshot.AirQuality(
                aqiText: index.aqiDisplay,
                category: index.category,
                primaryPollutant: index.primaryPollutant?.name ?? "无",
                colorHex: String(
                    format: "#%02X%02X%02X",
                    index.color.red,
                    index.color.green,
                    index.color.blue
                )
            )
        }

        return WeatherSkillSnapshot(
            location: location,
            current: currentWeather,
            hourly: Array(hourlyWeather),
            airQuality: airQualitySummary,
            updatedAt: updatedAt
        )
    }

    private func requestOptional<Response: Decodable>(
        credentials: Credentials,
        path: String,
        queryItems: [URLQueryItem]
    ) async -> Response? {
        do {
            return try await request(
                credentials: credentials,
                path: path,
                queryItems: queryItems
            )
        } catch {
            return nil
        }
    }

    private func request<Response: Decodable>(
        credentials: Credentials,
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> Response {
        var components = try Self.urlComponents(from: credentials.apiHost)
        components.path = path
        components.queryItems = queryItems

        guard let url = components.url else {
            throw WeatherSkillError.invalidHost
        }

        var request = URLRequest(url: url)
        request.setValue(credentials.apiKey, forHTTPHeaderField: "X-QW-Api-Key")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw WeatherSkillError.remote("天气服务请求失败，请检查 API Host、API Key 或网络状态。")
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw WeatherSkillError.invalidResponse
        }
    }

    private static func urlComponents(from apiHost: String) throws -> URLComponents {
        let trimmedHost = apiHost.trimmed
        guard !trimmedHost.isEmpty else {
            throw WeatherSkillError.missingCredentials
        }

        let normalized = trimmedHost.hasPrefix("http://") || trimmedHost.hasPrefix("https://")
            ? trimmedHost
            : "https://\(trimmedHost)"

        guard let components = URLComponents(string: normalized), components.host != nil else {
            throw WeatherSkillError.invalidHost
        }

        return components
    }

    private static func message(for code: String) -> String {
        switch code {
        case "204":
            return "没有找到对应城市，请重新选择。"
        case "400":
            return "天气请求参数无效，请检查 API Host 或城市配置。"
        case "401", "402", "403":
            return "和风天气认证失败，请检查 API Key 或订阅权限。"
        case "404":
            return "天气接口不存在，请检查 API Host。"
        case "429":
            return "天气接口请求过于频繁，请稍后再试。"
        case "500", "502", "503", "504":
            return "天气服务暂时不可用，请稍后再试。"
        default:
            return "天气服务返回了错误代码 \(code)。"
        }
    }

    private static func parseDate(_ string: String) -> Date? {
        if let date = Self.internetDateFormatter.date(from: string) {
            return date
        }
        if let date = Self.fractionalInternetDateFormatter.date(from: string) {
            return date
        }
        // 和风逐小时 `fxTime` 常见格式是 2026-05-04T20:00+08:00，没有秒，需要单独解析。
        if let date = Self.minuteOffsetDateFormatter.date(from: string) {
            return date
        }
        return Self.zuluFormatter.date(from: string)
    }

    private static func pathValue(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static let internetDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalInternetDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let minuteOffsetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mmXXXXX"
        return formatter
    }()

    private static let zuluFormatter: ISO8601DateFormatter = {
        ISO8601DateFormatter()
    }()
}

private struct GeoLookupResponse: Decodable {
    let code: String
    let location: [GeoLocationPayload]
}

private struct GeoLocationPayload: Decodable {
    let id: String
    let name: String
    let adm1: String
    let adm2: String
    let country: String
    let tz: String
    let lat: String
    let lon: String
}

private struct WeatherNowResponse: Decodable {
    let code: String
    let updateTime: String
    let now: WeatherNowPayload?
}

private struct WeatherNowPayload: Decodable {
    let obsTime: String
    let temp: String
    let feelsLike: String
    let icon: String
    let text: String
    let humidity: String
}

private struct WeatherHourlyResponse: Decodable {
    let code: String
    let hourly: [WeatherHourlyPayload]
}

private struct WeatherHourlyPayload: Decodable {
    let fxTime: String
    let temp: String
    let icon: String
    let text: String
}

private struct WeatherDailyResponse: Decodable {
    let code: String
    let daily: [WeatherDailyPayload]
}

private struct WeatherDailyPayload: Decodable {
    let tempMax: String
    let tempMin: String
}

private struct AirQualityResponse: Decodable {
    let indexes: [AirQualityIndexPayload]
}

private struct AirQualityIndexPayload: Decodable {
    let aqiDisplay: String
    let category: String
    let color: AirQualityColorPayload
    let primaryPollutant: AirQualityPollutantPayload?
}

private struct AirQualityColorPayload: Decodable {
    let red: Int
    let green: Int
    let blue: Int
}

private struct AirQualityPollutantPayload: Decodable {
    let name: String
}
