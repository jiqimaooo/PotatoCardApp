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
    @State private var syncMessage: String?

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

                if let syncMessage {
                    Text(syncMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(2)
                }

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

    private var canSync: Bool {
        // 没绑定设备时也允许触发——协调器会自动复用天气技能里的设备或当前连接设备。
        healthStore.config.isEnabled && !isSyncing
    }

    private func startSync() async {
        isSyncing = true
        syncMessage = "同步中…"
        // 打标，使「天气卡片」的进度按钮不会跟着走动画。
        bleService.beginSync(source: HealthSkillSectionView.syncSource)
        defer { bleService.endSync(source: HealthSkillSectionView.syncSource) }
        do {
            syncMessage = try await HealthSkillPushCoordinator.shared.pushHealthDashboard(
                mode: healthStore.config.defaultMode,
                waitForFinalResult: false
            )
        } catch {
            if let localized = error as? LocalizedError, let description = localized.errorDescription, !description.isEmpty {
                syncMessage = description
            } else {
                syncMessage = error.localizedDescription
            }
        }
        isSyncing = false
    }

    static let syncSource = "health"

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
                detailSection
                authorizationCard
                syncButton
                if let statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, AppBottomBarMetrics.scrollContentBottomPadding)
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

    // MARK: - 设置区（grouped rows，与天气看板保持一致）

    private var detailSection: some View {
        VStack(spacing: 0) {
            detailToggleRow(title: "技能开关", isOn: Binding(
                get: { store.config.isEnabled },
                set: { store.updateEnabled($0) }
            ))
            dividerRow
            detailNavigationRow(title: "默认看板", value: store.config.defaultMode.title) {
                HealthModePickerView(store: store)
            }
            dividerRow
            detailNavigationRow(title: "日常起床时间", value: wakeHourLabel) {
                HealthWakeHourPickerView(store: store)
            }
            dividerRow
            detailNavigationRow(title: "同步到设备", value: selectedDeviceLabel) {
                HealthDevicePickerView(store: store)
                    .environmentObject(bleService)
            }
        }
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        )
    }

    private func detailNavigationRow<Destination: View>(
        title: String,
        value: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(primaryTextColor)

                Spacer()

                Text(value)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
        }
    }

    private func detailToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(primaryTextColor)

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color(red: 0.18, green: 0.49, blue: 0.98))
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private var dividerRow: some View {
        Divider()
            .padding(.leading, 16)
    }

    private var selectedDevice: BleDevice? {
        let targetID = store.config.targetDeviceID.trimmed
        guard !targetID.isEmpty else { return nil }
        if let device = bleService.devices.first(where: { $0.id == targetID }) {
            return device
        }
        if let connected = bleService.connectedDevice, connected.id == targetID {
            return connected
        }
        if let selected = bleService.selectedDevice, selected.id == targetID {
            return selected
        }
        return nil
    }

    private var selectedDeviceLabel: String {
        if let selectedDevice {
            return selectedDevice.name
        }
        if let snapshot = store.config.targetDeviceSnapshot, !snapshot.id.trimmed.isEmpty {
            return snapshot.name
        }
        return "未选择"
    }

    private var wakeHourLabel: String {
        let h = store.config.dailyWakeHour
        return String(format: "%02d:00", h)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.94) : Color.black.opacity(0.92)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.66) : Color.black.opacity(0.56)
    }

    private var cardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.94)
    }

    private var cardStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)
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
        bleService.beginSync(source: HealthSkillSectionView.syncSource)
        defer { bleService.endSync(source: HealthSkillSectionView.syncSource) }
        do {
            if showsSampleData {
                let snapshot = HealthSkillMockData.snapshot(for: store.config.defaultMode)
                let message = try await HealthSkillPushCoordinator.shared.pushSnapshot(
                    snapshot,
                    using: store,
                    waitForFinalResult: false
                )
                statusMessage = "\(message)（示例数据）"
            } else {
                let message = try await HealthSkillPushCoordinator.shared.pushHealthDashboard(
                    mode: store.config.defaultMode,
                    waitForFinalResult: false
                )
                statusMessage = message
            }
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

// MARK: - 二级菜单：默认看板 / 同步设备
// 风格与天气看板下的 WeatherFrequencyPickerView / WeatherDevicePickerView 对齐。

private struct HealthModePickerView: View {
    @ObservedObject var store: HealthSkillStore
    // 点击瞬间先把高亮落在本地 @State，再异步推到 store，避免 SwiftUI 在 store 更新后
    // 把列表重建吃掉点击动画（同 WeatherFrequencyPickerView）。
    @State private var pendingSelection: HealthDashboardMode?

    private var currentSelection: HealthDashboardMode {
        pendingSelection ?? store.config.defaultMode
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Array(HealthDashboardMode.allCases.enumerated()), id: \.element) { index, mode in
                    Button {
                        guard pendingSelection != mode else { return }
                        pendingSelection = mode
                        Task { @MainActor in
                            store.updateDefaultMode(mode)
                            await store.refresh(mode: mode)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(mode.title)
                                    .font(.system(size: 16, weight: .medium))
                                Spacer()
                                if currentSelection == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color(red: 0.18, green: 0.49, blue: 0.98))
                                }
                            }
                            Text(mode.summary)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)

                    if index < HealthDashboardMode.allCases.count - 1 {
                        Divider()
                            .padding(.leading, 18)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("默认看板")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: store.config.defaultMode) { newValue in
            if pendingSelection == newValue { pendingSelection = nil }
        }
    }
}

private struct HealthDevicePickerView: View {
    @ObservedObject var store: HealthSkillStore
    @EnvironmentObject private var bleService: BleTransferService

    var body: some View {
        List {
            if let connected = bleService.connectedDevice {
                deviceRow(connected, label: "当前连接")
            }

            ForEach(bleService.devices.filter { $0.id != bleService.connectedDevice?.id }) { device in
                deviceRow(device, label: "可用设备")
            }
        }
        .navigationTitle("同步设备")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deviceRow(_ device: BleDevice, label: String) -> some View {
        Button {
            store.updateTargetDevice(device)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.config.targetDeviceID == device.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.18, green: 0.49, blue: 0.98))
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

// 日常起床时间 picker：0~23 小时整点；切分点 = 该时间 - 3 小时。
private struct HealthWakeHourPickerView: View {
    @ObservedObject var store: HealthSkillStore
    @State private var pendingHour: Int?

    private static let hours: [Int] = Array(0...23)

    private var currentHour: Int {
        pendingHour ?? store.config.dailyWakeHour
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                Text("用于划分睡眠日。起床时间 − 3 小时是切分点；跨切分点的睡眠会算到前一天。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)

                VStack(spacing: 0) {
                    ForEach(Array(Self.hours.enumerated()), id: \.element) { index, hour in
                        Button {
                            guard pendingHour != hour else { return }
                            pendingHour = hour
                            Task { @MainActor in
                                store.updateDailyWakeHour(hour)
                                await store.refresh(mode: store.config.defaultMode)
                            }
                        } label: {
                            HStack {
                                Text(String(format: "%02d:00", hour))
                                    .font(.system(size: 16, weight: .medium).monospacedDigit())
                                Spacer()
                                Text("切分点 \(String(format: "%02d:00", max(0, min(23, hour - 3))))")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                                if currentHour == hour {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color(red: 0.18, green: 0.49, blue: 0.98))
                                        .padding(.leading, 8)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)

                        if index < Self.hours.count - 1 {
                            Divider().padding(.leading, 18)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("日常起床时间")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: store.config.dailyWakeHour) { newValue in
            if pendingHour == newValue { pendingHour = nil }
        }
    }
}
