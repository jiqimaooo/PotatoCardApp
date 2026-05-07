import CoreGraphics
import Foundation

struct BleDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    let rawDevice: [AnyHashable: Any]
    let profile: EInkDeviceProfile
    let batteryVoltage: Double?
    let batteryPercent: Int?

    init(rawDevice: [AnyHashable: Any]) {
        let sanitizedRawDevice = BleDevice.sanitizedRawDevice(rawDevice)
        self.rawDevice = sanitizedRawDevice

        let rawName = sanitizedRawDevice["name"] as? String
        let rawMac = sanitizedRawDevice["mac"] as? String
        let rawMacAddress = sanitizedRawDevice["macAddress"] as? String
        let rawAddress = sanitizedRawDevice["address"] as? String

        // SDK 回调里常用 `macAddress` 保存设备编号，必须和 `mac` 一起纳入识别。
        let normalizedName = BleDevice.normalizedString(rawName)
        let normalizedMac = BleDevice.normalizedString(rawMac)
        let normalizedMacAddress = BleDevice.normalizedString(rawMacAddress)
        let normalizedAddress = BleDevice.normalizedString(rawAddress)

        self.name = normalizedName ?? normalizedMacAddress ?? normalizedMac ?? "未知设备"
        self.address = normalizedMacAddress ?? normalizedMac ?? normalizedAddress ?? ""
        self.id = normalizedMacAddress ?? normalizedMac ?? normalizedAddress ?? self.name
        // 设备型号表依赖 NEMR 编号，蓝牙名是 PICKSMART 时也要优先用编号匹配。
        let profileLookupName = normalizedMacAddress ?? normalizedMac ?? normalizedName ?? self.name
        self.profile = EInkDeviceProfile.profile(for: profileLookupName)
        let parsedVoltage = BleDevice.parseBatteryVoltage(from: sanitizedRawDevice)
        self.batteryVoltage = parsedVoltage
        self.batteryPercent = BleDevice.parseBatteryPercent(from: sanitizedRawDevice)
            ?? parsedVoltage.map { BleDevice.estimatedBatteryPercent(fromVoltage: $0) }
    }

    static func == (lhs: BleDevice, rhs: BleDevice) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var targetSnapshot: WeatherTargetDeviceSnapshot {
        WeatherTargetDeviceSnapshot(device: self)
    }

    var sdkTransferDevice: [AnyHashable: Any] {
        // 传回 PickBleManager 前补齐稳定字段，避免 SDK 读到 Optional/空值后中断后台传输。
        var device = rawDevice.filter { _, value in
            !(value is NSNull)
        }

        let stableName = name.isEmpty ? id : name
        let stableAddress = address.isEmpty ? id : address

        device["name"] = BleDevice.normalizedString(device["name"] as? String) ?? stableName
        device["mac"] = BleDevice.normalizedString(device["mac"] as? String) ?? stableAddress
        device["macAddress"] = BleDevice.normalizedString(device["macAddress"] as? String) ?? stableAddress
        device["address"] = BleDevice.normalizedString(device["address"] as? String) ?? stableAddress

        return device
    }

    var debugSummary: String {
        let voltageText = batteryVoltage.map { String(format: "%.2fV", $0) } ?? "nil"
        return "name=\(name), address=\(address.isEmpty ? "<empty>" : address), id=\(id), battery=\(batteryPercent.map(String.init) ?? "nil"), voltage=\(voltageText), profile=\(profile.name) \(profile.displaySize), raw=\(debugRawSummary)"
    }

    private var debugRawSummary: String {
        let keys = rawDevice.keys
            .map { String(describing: $0) }
            .sorted()

        let pairs = keys.map { key in
            let value = rawDevice.first { String(describing: $0.key) == key }?.value
            return "\(key)=\(String(describing: value))"
        }

        return "{\(pairs.joined(separator: ", "))}"
    }

    private static func parseBatteryPercent(from rawDevice: [AnyHashable: Any]) -> Int? {
        let preferredKeys = ["bettery", "battery", "batteryLevel", "electricity"]

        for key in preferredKeys {
            guard let rawValue = rawDevice[key] else { continue }
            if let percent = normalizedBatteryPercent(from: rawValue) {
                return percent
            }
        }

        return nil
    }

    private static func parseBatteryVoltage(from rawDevice: [AnyHashable: Any]) -> Double? {
        let preferredKeys = ["power", "voltage", "batteryVoltage"]

        for key in preferredKeys {
            guard let rawValue = rawDevice[key] else { continue }
            if let voltage = normalizedBatteryVoltage(from: rawValue) {
                return voltage
            }
        }

        return nil
    }

    private static func sanitizedRawDevice(_ rawDevice: [AnyHashable: Any]) -> [AnyHashable: Any] {
        var sanitizedDevice: [AnyHashable: Any] = [:]

        for (key, value) in rawDevice {
            guard let sanitizedValue = sanitizedObjectiveCValue(value) else { continue }
            sanitizedDevice[key] = sanitizedValue
        }

        return sanitizedDevice
    }

    private static func sanitizedObjectiveCValue(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)

        // SDK 回调有时会把 Optional 包装值塞进 Swift 字典；传回 Objective-C 前必须解包。
        if mirror.displayStyle == .optional {
            guard let child = mirror.children.first else { return nil }
            return sanitizedObjectiveCValue(child.value)
        }

        guard !(value is NSNull) else { return nil }

        if let dictionary = value as? [AnyHashable: Any] {
            return sanitizedRawDevice(dictionary)
        }

        if let array = value as? [Any] {
            return array.compactMap { sanitizedObjectiveCValue($0) }
        }

        return value
    }

    // 统一清洗字符串，避免 Optional 包装值或空串参与设备识别。
    private static func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }

        return trimmedValue
    }

    private static func normalizedBatteryPercent(from rawValue: Any) -> Int? {
        let normalizedString: String?
        let value: Double?

        if let number = rawValue as? NSNumber {
            normalizedString = nil
            value = number.doubleValue
        } else if let string = rawValue as? String {
            normalizedString = string
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "%", with: "")
            value = Double(normalizedString ?? "")
        } else {
            normalizedString = nil
            value = nil
        }

        guard let value else { return nil }

        let percent = value <= 1 ? value * 100 : value
        guard percent >= 0, percent <= 100 else { return nil }

        return Int(percent.rounded())
    }

    private static func normalizedBatteryVoltage(from rawValue: Any) -> Double? {
        let value: Double?

        if let number = rawValue as? NSNumber {
            value = number.doubleValue
        } else if let string = rawValue as? String {
            let normalizedString = string
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "V", with: "")
                .replacingOccurrences(of: "v", with: "")
            value = Double(normalizedString)
        } else {
            value = nil
        }

        guard let value else { return nil }

        // 协议里 power 是电压放大 10 倍，例如 32 代表 3.2V。
        if (20...60).contains(value) {
            return value / 10
        }

        if (2...6).contains(value) {
            return value
        }

        return nil
    }

    private static func estimatedBatteryPercent(fromVoltage voltage: Double) -> Int {
        let points: [(voltage: Double, percent: Double)] = [
            (3.20, 100),
            (3.10, 80),
            (3.00, 55),
            (2.90, 35),
            (2.80, 20),
            (2.70, 10),
            (2.60, 0)
        ]

        if voltage >= points[0].voltage {
            return Int(points[0].percent)
        }

        if voltage <= points[points.count - 1].voltage {
            return Int(points[points.count - 1].percent)
        }

        for index in 0..<(points.count - 1) {
            let upper = points[index]
            let lower = points[index + 1]
            guard voltage <= upper.voltage, voltage >= lower.voltage else { continue }

            let ratio = (voltage - lower.voltage) / (upper.voltage - lower.voltage)
            let percent = lower.percent + ratio * (upper.percent - lower.percent)
            return min(100, max(0, Int(percent.rounded())))
        }

        return 0
    }
}

struct EInkDeviceProfile: Equatable {
    static let fallback = EInkDeviceProfile(
        name: "未知型号",
        pixelSize: CGSize(width: 400, height: 600),
        colorMode: .sixColor,
        isFallback: true
    )

    let name: String
    let pixelSize: CGSize
    let colorMode: EInkColorMode
    let isFallback: Bool

    var displaySize: String {
        "\(Int(pixelSize.width)) x \(Int(pixelSize.height))"
    }

    static func profile(for deviceName: String) -> EInkDeviceProfile {
        switch deviceName {
        case "NEMR92128526":
            return EInkDeviceProfile(name: "2.1 寸", pixelSize: CGSize(width: 250, height: 128), colorMode: .monochrome, isFallback: false)
        case "NEMR92957953", "NEMR92984868":
            return EInkDeviceProfile(name: "2.9 寸黑白红", pixelSize: CGSize(width: 296, height: 128), colorMode: .blackWhiteRed, isFallback: false)
        case "NEMR99833123":
            return EInkDeviceProfile(name: "10.2 寸", pixelSize: CGSize(width: 960, height: 640), colorMode: .monochrome, isFallback: false)
        case "NEMR99836136":
            return EInkDeviceProfile(name: "4.0 寸", pixelSize: CGSize(width: 528, height: 768), colorMode: .blackWhiteRedYellow, isFallback: false)
        default:
            return fallback
        }
    }
}

enum EInkColorMode: String, Codable, Equatable {
    case monochrome
    case blackWhiteRed
    case blackWhiteRedYellow
    case sixColor
}
