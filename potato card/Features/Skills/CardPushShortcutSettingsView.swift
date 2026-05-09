//
//  CardPushShortcutSettingsView.swift
//  potato card
//
//  「推送图片/文字到土豆片」快捷指令的偏好设置入口。
//

import SwiftUI

struct CardPushShortcutSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(CardPushPreferenceKeys.autoSyncPendingPush) private var autoSyncPendingPush = true
    @AppStorage(CardPushPreferenceKeys.saveImageToGallery) private var saveImageToGallery = true
    @AppStorage(CardPushPreferenceKeys.saveTextToGallery) private var saveTextToGallery = true
    @AppStorage(CardPushPreferenceKeys.compatibilityProbeEnabled) private var compatibilityProbeEnabled = false

    @State private var pendingTaskCount: Int = 0

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $autoSyncPendingPush) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("可用时同步最近一次推送")
                            .font(.system(size: 15, weight: .medium))
                        Text("App 后台运行扫不到设备时，下次回到前台自动重新推送上次失败的卡片。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(accentColor)

                if pendingTaskCount > 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "tray.full")
                            .foregroundStyle(accentColor)
                        Text("当前等待重推：\(pendingTaskCount) 张")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button("清空") {
                            for task in PendingCardPushQueue.loadAll() {
                                PendingCardPushQueue.remove(id: task.id)
                            }
                            refreshPendingCount()
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("队列同步")
            } footer: {
                Text("关闭后，快捷指令推送失败时会直接报错，不会自动加入队列。")
                    .font(.system(size: 11))
            }

            Section {
                Toggle(isOn: $saveImageToGallery) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("图片快捷指令存入图库")
                            .font(.system(size: 15, weight: .medium))
                        Text("通过「推送图片到土豆片」生成的卡片自动加到 App 图库。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(accentColor)

                Toggle(isOn: $saveTextToGallery) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("文字快捷指令存入图库")
                            .font(.system(size: 15, weight: .medium))
                        Text("通过「推送文字到土豆片」生成的卡片自动加到 App 图库。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(accentColor)
            } header: {
                Text("图库存储")
            } footer: {
                Text("关闭后只推送到设备，不在 App 图库里留底。")
                    .font(.system(size: 11))
            }

            Section {
                Toggle(isOn: $compatibilityProbeEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("兼容性增强（测试）")
                            .font(.system(size: 15, weight: .medium))
                        Text("快捷指令在后台扫描设备时，并行用 CoreBluetooth 服务过滤扫描（FEF0）+ State Restoration，提高弱广播设备的命中率。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(accentColor)
            } header: {
                Text("实验功能")
            } footer: {
                Text("仅对此前在 App 里成功扫描过的设备生效。开启后下次启动 App 才完整生效（CoreBluetooth 状态保留需要在启动期注册）。")
                    .font(.system(size: 11))
            }
        }
        .navigationTitle("快捷指令设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshPendingCount()
        }
    }

    private var accentColor: Color {
        Color(red: 0.18, green: 0.49, blue: 0.98)
    }

    private func refreshPendingCount() {
        pendingTaskCount = PendingCardPushQueue.loadAll().count
    }
}

#Preview {
    NavigationStack {
        CardPushShortcutSettingsView()
    }
}
