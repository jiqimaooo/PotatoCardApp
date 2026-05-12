//
//  CachedSDKDeviceDictStore.swift
//  potato card
//
//  缓存 PickBleManager 在前台 bluetoothSearchDevice 回调里给我们的完整 rawDevice 字典。
//  后台 CompatProbe 走 CoreBluetooth 直接发现 peripheral 时，
//  可以拿这份缓存里的字段（type/version/power 等 SDK 内部依赖的 key）补齐字典，
//  避免 SDK 读到 nil 触发 NSInvalidArgumentException。
//

import Foundation

enum CachedSDKDeviceDictStore {
    nonisolated private static let key = "cachedSDKDeviceDictByDeviceID"

    nonisolated static func save(deviceID: String, rawDevice: [AnyHashable: Any]) {
        let trimmedID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }

        // 把不可序列化的字段（如 CBPeripheral）剔除，只缓存 SDK 业务字段。
        let serializable = rawDevice.filter { _, value in
            isPropertyListSerializable(value)
        }
        let stringKeyed = Dictionary(uniqueKeysWithValues: serializable.compactMap { key, value -> (String, Any)? in
            guard let stringKey = key as? String else { return nil }
            return (stringKey, value)
        })
        guard !stringKeyed.isEmpty else { return }

        var map = (UserDefaults.standard.dictionary(forKey: key)) ?? [:]
        map[trimmedID] = stringKeyed
        UserDefaults.standard.set(map, forKey: key)
    }

    nonisolated static func load(deviceID: String) -> [AnyHashable: Any]? {
        let trimmed = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let map = UserDefaults.standard.dictionary(forKey: key) else { return nil }
        guard let stored = map[trimmed] as? [String: Any] else { return nil }
        var result: [AnyHashable: Any] = [:]
        for (k, v) in stored {
            result[AnyHashable(k)] = v
        }
        return result
    }

    nonisolated private static func isPropertyListSerializable(_ value: Any) -> Bool {
        // UserDefaults 只接受 NSData/NSString/NSDate/NSNumber/NSArray/NSDictionary。
        switch value {
        case is String, is NSString, is NSNumber, is Bool, is Int, is Double, is Data, is NSData, is Date:
            return true
        case let array as [Any]:
            return array.allSatisfy(isPropertyListSerializable)
        case let dict as [String: Any]:
            return dict.values.allSatisfy(isPropertyListSerializable)
        default:
            return false
        }
    }
}
