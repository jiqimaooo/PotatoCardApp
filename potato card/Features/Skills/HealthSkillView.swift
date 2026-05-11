//
//  HealthSkillView.swift
//  potato card
//
//  健康看板在“技能”首页里的卡片 + 设置详情页。
//  与 WeatherSkillStore/WeatherSkillDetailView 同构：
//  - HealthSkillSectionView 是技能首页里的横向卡片，提供开关/快速同步入口。
//  - HealthSkillDetailView 是 NavigationLink 跳转后的设置页，提供模式切换、立即同步、设备绑定。
//

import SwiftUI
import UIKit

struct HealthSkillSectionView: View {
    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var healthStore = HealthSkillStore()
    @State private var isSyncing = false
    @State private var lastSyncMessage: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.95, green: 0.30, blue: 0.40),
                                    Color(red: 0.98, green: 0.62, blue: 0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)
                        .overlay(
                            Image(systemName: "heart.text.square")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.white)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("健康看板")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(primaryTextColor)

                        Text(healthStore.skill.previewSummary)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Toggle("", isOn: Binding(
                        get: { healthStore.config.isEnabled },
                        set: { healthStore.updateEnabled($0) }
                    ))
                    .labelsHidden()
                    .scaleEffect(0.92)
                    .tint(accentColor)
                }

                Text(metaText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(primaryTextColor.opacity(0.78))
                    .lineLimit(1)

                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Button {
                        Task { await startSync() }
                    } label: {
                        Text(isSyncing ? "同步中…" : "立即同步")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(canSync ? accentColor : accentColor.opacity(0.45), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSync || isSyncing)

                    NavigationLink {
                        HealthSkillDetailView(store: healthStore)
                            .environmentObject(bleService)
                    } label: {
                        Text("设置")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 84, height: 38)
                            .background(buttonFillColor, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(cardStrokeColor, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(primaryTextColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HealthSkillPreviewView(store: healthStore)
                .frame(width: 88, height: 132)
        }
        .padding(14)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.035), radius: 10, x: 0, y: 4)
        .frame(height: 160)
        // 进入“技能”页时不主动请求 HealthKit 授权——只在用户主动打开开关或进入详情页时请求。
    }

    private var metaText: String {
        "\(healthStore.config.defaultMode.title) · 400 x 600"
    }

    private var statusText: String {
        if let message = lastSyncMessage { return message }
        if let date = healthStore.skill.lastSyncAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d HH:mm"
            return "\(healthStore.loadState.message) · 上次同步 \(formatter.string(from: date))"
        }
        return healthStore.loadState.message
    }

    private var statusColor: Color {
        switch healthStore.loadState {
        case .failed:
            return .red
        case .missingAuthorization:
            return Color(red: 0.94, green: 0.52, blue: 0.14)
        default:
            return secondaryTextColor
        }
    }

    private var canSync: Bool {
        // 没绑定设备时也允许触发——协调器会自动复用天气技能里的设备或当前连接设备。
        healthStore.config.isEnabled && !isSyncing
    }

    private func startSync() async {
        isSyncing = true
        lastSyncMessage = "同步中…"
        do {
            let message = try await HealthSkillPushCoordinator.shared.pushHealthDashboard(
                mode: healthStore.config.defaultMode,
                waitForFinalResult: false
            )
            lastSyncMessage = message
        } catch {
            if let localized = error as? LocalizedError, let description = localized.errorDescription, !description.isEmpty {
                lastSyncMessage = description
            } else {
                lastSyncMessage = error.localizedDescription
            }
        }
        isSyncing = false
    }

    private var accentColor: Color { Color(red: 0.18, green: 0.49, blue: 0.98) }
    private var primaryTextColor: Color { colorScheme == .dark ? Color.white.opacity(0.94) : Color.black.opacity(0.92) }
    private var secondaryTextColor: Color { colorScheme == .dark ? Color.white.opacity(0.66) : Color.black.opacity(0.56) }
    private var cardFillColor: Color { colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.94) }
    private var cardStrokeColor: Color { colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06) }
    private var buttonFillColor: Color { colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04) }
}

private struct HealthSkillPreviewView: View {
    @ObservedObject var store: HealthSkillStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.035), radius: 6, x: 0, y: 3)

            if let image = previewImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 78, height: 118)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VStack(spacing: 6) {
                    Image(systemName: store.config.defaultMode.systemImage)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(store.config.defaultMode.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var previewImage: UIImage? {
        if let snapshot = store.snapshot {
            return HealthSkillRenderer.renderDisplayImage(snapshot: snapshot, targetSize: CGSize(width: 400, height: 600))
        }
        return HealthSkillRenderer.renderPlaceholder(mode: store.config.defaultMode)
    }
}

// MARK: - 详情设置页

struct HealthSkillDetailView: View {
    @ObservedObject var store: HealthSkillStore
    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.colorScheme) private var colorScheme

    @State private var isSyncing = false
    @State private var statusMessage: String?
    @State private var hasAttemptedAuthorization = false
    // 调试用：当 HealthKit 读不到数据时（模拟器、首次安装），切到示例数据预览，
    // 便于检查 400x600 渲染布局是否合理。打包发版不需要隐藏，本身是个无害的展示开关。
    @State private var showsSampleData = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                previewCard
                modeSelector
                authorizationCard
                deviceCard
                syncButton
                if let statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .navigationTitle("健康看板")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !hasAttemptedAuthorization {
                hasAttemptedAuthorization = true
                await store.onAppear()
                // 进入页面时主动取一次默认模式数据，方便预览。
                await store.refresh(mode: store.config.defaultMode)
            }
        }
    }

    private var previewCard: some View {
        VStack(spacing: 8) {
            Image(uiImage: previewImage)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(maxWidth: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
            // 实时把读取状态打出来，避免再出现「页面只显示占位图但用户已经授权」的情况下
            // 看不到错误原因。
            Text(store.loadState.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(loadStateColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
            HStack(spacing: 10) {
                Text("400 x 600 墨水屏预览")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Button {
                    showsSampleData.toggle()
                } label: {
                    Text(showsSampleData ? "示例数据 开" : "示例数据 关")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(showsSampleData ? Color.accentColor : Color.gray, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var previewImage: UIImage {
        if showsSampleData {
            return HealthSkillRenderer.renderDisplayImage(
                snapshot: HealthSkillMockData.snapshot(for: store.config.defaultMode),
                targetSize: CGSize(width: 400, height: 600)
            )
        }
        if let snapshot = store.snapshot {
            return HealthSkillRenderer.renderDisplayImage(snapshot: snapshot, targetSize: CGSize(width: 400, height: 600))
        }
        return HealthSkillRenderer.renderPlaceholder(mode: store.config.defaultMode)
    }

    private var loadStateColor: Color {
        switch store.loadState {
        case .failed, .missingAuthorization:
            return Color(red: 0.85, green: 0.22, blue: 0.18)
        case .loading:
            return .secondary
        case .loaded:
            return Color(red: 0.18, green: 0.55, blue: 0.30)
        case .idle:
            return .secondary
        }
    }

    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("默认看板模式")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Picker("默认看板模式", selection: Binding(
                get: { store.config.defaultMode },
                set: { newValue in
                    store.updateDefaultMode(newValue)
                    Task { await store.refresh(mode: newValue) }
                }
            )) {
                ForEach(HealthDashboardMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(store.config.defaultMode.summary)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var authorizationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.tint)
                Text("健康数据授权")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            Text(store.isHealthDataAvailable
                 ? "首次打开会请求授权。如未弹窗，可前往：系统设置 → 健康 → 数据访问与设备 → Tatoo!，手动开启读取权限。"
                 : "当前设备不支持健康数据。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Button {
                Task { await store.requestAuthorization() }
            } label: {
                Text("重新请求授权")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!store.isHealthDataAvailable)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.tint)
                Text("同步设备")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            if let snapshot = store.config.targetDeviceSnapshot {
                Text("\(snapshot.name) · \(snapshot.pixelWidth) x \(snapshot.pixelHeight)")
                    .font(.system(size: 13, weight: .medium))
            } else if let device = bleService.connectedDevice ?? bleService.selectedDevice {
                Text("将自动使用：\(device.name)")
                    .font(.system(size: 13, weight: .medium))
            } else {
                Text("尚未绑定。健康看板会自动复用天气技能里的同步设备，也可以在“设备”页连接一台土豆片。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let device = bleService.connectedDevice ?? bleService.selectedDevice,
               store.config.targetDeviceID.trimmed.isEmpty || store.config.targetDeviceID != device.id {
                Button {
                    store.updateTargetDevice(device)
                } label: {
                    Text("绑定到当前设备")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var syncButton: some View {
        Button {
            Task { await runSync() }
        } label: {
            Text(isSyncing ? "正在同步…" : "立即同步到墨水屏")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color.accentColor.opacity(isSyncing ? 0.55 : 1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSyncing || !store.config.isEnabled)
    }

    private func runSync() async {
        isSyncing = true
        statusMessage = "同步中…"
        do {
            let message = try await HealthSkillPushCoordinator.shared.pushHealthDashboard(
                mode: store.config.defaultMode,
                waitForFinalResult: false
            )
            statusMessage = message
        } catch {
            if let localized = error as? LocalizedError, let description = localized.errorDescription, !description.isEmpty {
                statusMessage = description
            } else {
                statusMessage = error.localizedDescription
            }
        }
        isSyncing = false
    }
}
