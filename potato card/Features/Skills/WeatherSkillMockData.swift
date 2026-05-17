import Foundation

enum WeatherSkillMockData {
    static func snapshot(now: Date = Date()) -> WeatherSkillSnapshot {
        let calendar = Calendar.current
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let location = WeatherLocationOption(
            id: "101280601",
            name: "深圳",
            admin1: "广东",
            admin2: "深圳",
            country: "中国",
            timezone: "Asia/Shanghai",
            coordinate: WeatherCoordinate(latitude: 22.55, longitude: 114.06)
        )
        let current = WeatherSkillSnapshot.CurrentWeather(
            observedAt: now,
            temperature: 27,
            feelsLike: 29,
            conditionText: "多云",
            iconCode: "101",
            tempMax: 30,
            tempMin: 24,
            humidity: 68
        )
        let hourlySpecs: [(temperature: Int, condition: String, iconCode: String)] = [
            (27, "多云", "101"),
            (28, "晴间多云", "102"),
            (29, "晴", "100"),
            (28, "多云", "101"),
            (26, "小雨", "305"),
            (25, "阴", "104")
        ]
        let hourly = hourlySpecs.enumerated().compactMap { index, spec in
            calendar.date(byAdding: .hour, value: index + 1, to: hourStart).map { date in
                WeatherSkillSnapshot.HourlyWeather(
                    date: date,
                    temperature: spec.temperature,
                    conditionText: spec.condition,
                    iconCode: spec.iconCode
                )
            }
        }
        let airQuality = WeatherSkillSnapshot.AirQuality(
            aqiText: "42",
            category: "优",
            primaryPollutant: "PM2.5",
            colorHex: "#55C271"
        )

        return WeatherSkillSnapshot(
            location: location,
            current: current,
            hourly: hourly,
            airQuality: airQuality,
            updatedAt: now
        )
    }
}
