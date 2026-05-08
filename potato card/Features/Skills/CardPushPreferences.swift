//
//  CardPushPreferences.swift
//  potato card
//
//  快捷指令推送相关的用户偏好（图库 / 队列同步）。
//  用 ObservableObject + AppStorage 即可，跨进程读取（AppIntent 后台进程）依赖 UserDefaults 的进程间一致性。
//

import Foundation
import SwiftUI

enum CardPushPreferenceKeys {
    static let autoSyncPendingPush = "cardPush.autoSyncPendingPush"
    static let saveImageToGallery = "cardPush.saveImageShortcutToGallery"
    static let saveTextToGallery = "cardPush.saveTextShortcutToGallery"
    static let compatibilityProbeEnabled = "cardPush.compatibilityProbeEnabled"
}

// AppIntent 后台进程不能依赖 SwiftUI 环境，所以单独提供静态访问。
enum CardPushPreferences {
    nonisolated static var autoSyncPendingPush: Bool {
        readBool(CardPushPreferenceKeys.autoSyncPendingPush, default: true)
    }

    nonisolated static var saveImageToGallery: Bool {
        readBool(CardPushPreferenceKeys.saveImageToGallery, default: true)
    }

    nonisolated static var saveTextToGallery: Bool {
        readBool(CardPushPreferenceKeys.saveTextToGallery, default: true)
    }

    // 实验功能：开启后在后台扫描时用独立 CBCentralManager 主动 connect
    // 上次保存的 peripheral，提高弱广播设备的命中率。默认关闭，需要用户主动开启。
    nonisolated static var compatibilityProbeEnabled: Bool {
        readBool(CardPushPreferenceKeys.compatibilityProbeEnabled, default: false)
    }

    nonisolated private static func readBool(_ key: String, default defaultValue: Bool) -> Bool {
        // UserDefaults.object 返回 nil 才表示用户没设置过，此时使用默认值。
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: key)
    }
}
