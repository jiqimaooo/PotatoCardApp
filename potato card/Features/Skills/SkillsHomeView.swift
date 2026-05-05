import SwiftUI
import UIKit

struct SkillsHomeView: View {
    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var weatherStore = WeatherSkillStore()
    @State private var syncContext: WeatherSkillSyncContext?
    @State private var showsComingSoon = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                weatherSkillCard
                upcomingSkillCard
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .task {
            await weatherStore.onAppear()
            backfillTargetDeviceSelectionIfNeeded()
        }
        .onChange(of: bleService.connectedDevice?.id) { _, _ in
            backfillTargetDeviceSelectionIfNeeded()
        }
        .onChange(of: bleService.selectedDevice?.id) { _, _ in
            backfillTargetDeviceSelectionIfNeeded()
        }
        .alert("更多技能即将上线", isPresented: $showsComingSoon) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("图片、自定义、日历等技能会继续接到这个页面里。")
        }
        .fullScreenCover(item: $syncContext) { context in
            WeatherSkillSyncView(
                context: context,
                onSynchronized: {
                    weatherStore.markSynced()
                }
            )
            .environmentObject(bleService)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("技能")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(primaryTextColor)

                Text("管理你的技能")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
            }

            Spacer()

            Button {
                showsComingSoon = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                    .frame(width: 32, height: 32)
                    .background(buttonFillColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(cardStrokeColor, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var weatherSkillCard: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.20, green: 0.64, blue: 0.98),
                                    Color(red: 0.98, green: 0.71, blue: 0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)
                        .overlay(
                            Image(systemName: "cloud.sun.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.white)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("天气看板")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(primaryTextColor)

                        Text(weatherStore.skill.previewSummary)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Toggle("", isOn: Binding(
                        get: { weatherStore.config.isEnabled },
                        set: { weatherStore.updateEnabled($0) }
                    ))
                    .labelsHidden()
                    .scaleEffect(0.92)
                    .tint(accentColor)
                }

                Text(compactMetaText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(primaryTextColor.opacity(0.78))
                    .lineLimit(1)

                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Button {
                        syncContext = makeSyncContext()
                    } label: {
                        Text("立即同步")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(accentColor, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .opacity(makeSyncContext() == nil ? 0.45 : 1)
                    .disabled(makeSyncContext() == nil)

                    NavigationLink {
                        WeatherSkillDetailView(
                            store: weatherStore,
                            onSyncRequested: {
                                syncContext = makeSyncContext()
                            }
                        )
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

            weatherPreview
                .frame(width: 88, height: 132)
        }
        .padding(14)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.035), radius: 10, x: 0, y: 4)
    }

    private var upcomingSkillCard: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.95, green: 0.96, blue: 0.98))
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color(red: 0.52, green: 0.54, blue: 0.60))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("日历看板")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                Text("展示日程和重要安排")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Text("即将上线")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.56, blue: 0.16))
        }
        .padding(14)
        .background(cardFillColor.opacity(0.95), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.10 : 0.025), radius: 8, x: 0, y: 3)
    }

    private var weatherPreview: some View {
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
                    Image(systemName: "cloud.sun")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                    Text("天气预览")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                }
            }
        }
    }

    private var compactMetaText: String {
        "\(weatherLocationLabel) · \(weatherStore.config.updateFrequency.title) · \(weatherStore.config.template.title)"
    }

    private var statusText: String {
        if let syncText = syncTimeText {
            return "\(weatherStore.loadState.message) · 上次同步 \(syncText)"
        }
        return weatherStore.loadState.message
    }

    private var statusColor: Color {
        if case .failed = weatherStore.loadState {
            return .red
        }
        if weatherStore.loadState == .missingCredentials {
            return Color(red: 0.94, green: 0.52, blue: 0.14)
        }
        return secondaryTextColor
    }

    private var syncTimeText: String? {
        guard let date = weatherStore.skill.lastSyncAt else { return nil }
        return Self.syncTimeFormatter.string(from: date)
    }

    private var weatherLocationLabel: String {
        switch weatherStore.config.cityMode {
        case .automatic:
            return weatherStore.snapshot?.location.name ?? "当前位置"
        case .fixed:
            return weatherStore.config.fixedLocation?.name ?? weatherStore.config.fixedCityQuery.trimmed
        }
    }

    private var previewImage: UIImage? {
        guard let snapshot = weatherStore.snapshot else { return nil }
        let targetSize = CGSize(width: 400, height: 600)
        return WeatherSkillRenderer.renderDisplayImage(
            snapshot: snapshot,
            template: weatherStore.config.template,
            targetSize: targetSize
        )
    }

    private func makeSyncContext() -> WeatherSkillSyncContext? {
        guard let snapshot = weatherStore.snapshot else { return nil }
        guard let device = selectedTargetDevice ?? activeDevice else { return nil }

        let prepared = WeatherSkillPushCoordinator.shared.preparePush(
            snapshot: snapshot,
            configuration: weatherStore.config,
            targetDeviceSnapshot: device.targetSnapshot
        )

        return WeatherSkillSyncContext(
            displayImage: prepared.displayImage,
            transferImage: prepared.transferImage,
            device: device
        )
    }

    private var selectedTargetDevice: BleDevice? {
        let targetID = weatherStore.config.targetDeviceID.trimmed
        guard !targetID.isEmpty else { return nil }
        if let connected = bleService.connectedDevice, connected.id == targetID {
            return connected
        }
        if let selected = bleService.selectedDevice, selected.id == targetID {
            return selected
        }
        return bleService.devices.first(where: { $0.id == targetID })
    }

    private var activeDevice: BleDevice? {
        bleService.connectedDevice ?? bleService.selectedDevice
    }

    private var accentColor: Color {
        Color(red: 0.18, green: 0.49, blue: 0.98)
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

    private var buttonFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }

    // 旧版本可能只在蓝牙服务里保留了当前设备，没有真正写进天气技能配置，这里顺手补齐一次。
    private func backfillTargetDeviceSelectionIfNeeded() {
        let targetID = weatherStore.config.targetDeviceID.trimmed

        if targetID.isEmpty, let snapshot = weatherStore.config.targetDeviceSnapshot {
            weatherStore.updateTargetDeviceSnapshot(snapshot)
            return
        }

        guard let activeDevice = bleService.connectedDevice ?? bleService.selectedDevice else { return }

        if targetID.isEmpty {
            weatherStore.updateTargetDevice(activeDevice)
            return
        }

        if targetID == activeDevice.id, weatherStore.config.targetDeviceSnapshot == nil {
            weatherStore.updateTargetDevice(activeDevice)
        }
    }

    private static let syncTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()
}

private enum WeatherCredentialKind: String, Identifiable {
    case apiHost
    case apiKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apiHost:
            return "API Host"
        case .apiKey:
            return "API Key"
        }
    }

    var placeholder: String {
        switch self {
        case .apiHost:
            return "abcxyz.qweatherapi.com"
        case .apiKey:
            return "请输入你的和风天气 API Key"
        }
    }

    var usesSecureInput: Bool {
        self == .apiKey
    }
}

private struct WeatherSkillDetailView: View {
    @ObservedObject var store: WeatherSkillStore
    let onSyncRequested: () -> Void

    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.colorScheme) private var colorScheme
    @State private var editingCredentialKind: WeatherCredentialKind?
    @State private var editingCredentialText = ""

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                previewCard
                detailSection
                apiSection
                actionsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .navigationTitle("天气看板")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingCredentialKind) { kind in
            credentialEditorSheet(for: kind)
        }
    }

    private var previewCard: some View {
        VStack(spacing: 14) {
            weatherPreview
                .frame(height: 260)

            HStack {
                Text(store.snapshot?.summaryText ?? "等待天气数据")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(primaryTextColor)

                Spacer()

                Text(store.loadState.message)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
            }
        }
        .padding(18)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        )
    }

    private var weatherPreview: some View {
        ZStack {
            Image("ink_tatoo2")
                .resizable()
                .scaledToFit()
                .frame(width: 210, height: 270)

            if let image = previewImage {
                // 设备模型图是 480x764，内屏约 400x600。
                // 这里按模型缩放后的内屏尺寸贴图，避免天气图过大压窄上边框。
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 143, height: 212)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .offset(y: -16)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var detailSection: some View {
        VStack(spacing: 0) {
            detailToggleRow(title: "技能开关", isOn: Binding(
                get: { store.config.isEnabled },
                set: { store.updateEnabled($0) }
            ))
            dividerRow
            detailNavigationRow(title: "城市模式", value: store.config.cityMode.title) {
                WeatherCitySelectionView(store: store)
            }
            dividerRow
            detailNavigationRow(title: "更新频率", value: store.config.updateFrequency.title) {
                WeatherFrequencyPickerView(store: store)
            }
            dividerRow
            detailToggleRow(title: "空气质量", isOn: Binding(
                get: { store.config.showsAirQuality },
                set: { store.updateShowsAirQuality($0) }
            ))
            dividerRow
            detailNavigationRow(title: "显示模板", value: store.config.template.title) {
                WeatherTemplatePickerView(store: store)
            }
            dividerRow
            detailNavigationRow(title: "同步到设备", value: selectedDeviceLabel) {
                WeatherDevicePickerView(store: store)
                    .environmentObject(bleService)
            }
        }
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        )
    }

    private var apiSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("和风天气配置")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(primaryTextColor)

            Text("请配置和风天气 API Host 和 API Key，注意数据保护")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(secondaryTextColor)

            VStack(spacing: 12) {
                credentialField(kind: .apiHost)
                credentialField(kind: .apiKey)
            }

            Button {
                Task {
                    await store.refreshWeather()
                }
            } label: {
                Label("刷新天气", systemImage: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        )
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Text("快捷指令“天气推送”会默认推送到这里选中的设备。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(secondaryTextColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onSyncRequested()
            } label: {
                Text("立即同步")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.18, green: 0.49, blue: 0.98))
            .disabled(previewImage == nil || selectedDevice == nil)

            NavigationLink {
                WeatherAutomationGuideView()
            } label: {
                Text("快捷指令说明")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color.black.opacity(colorScheme == .dark ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(cardStrokeColor, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(primaryTextColor)
        }
    }

    private func credentialField(kind: WeatherCredentialKind) -> some View {
        let value = credentialValue(for: kind)

        return VStack(alignment: .leading, spacing: 8) {
            Text(kind.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(primaryTextColor)

            Button {
                editingCredentialText = value
                editingCredentialKind = kind
            } label: {
                HStack(spacing: 10) {
                    Text(maskedCredential(value))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(value.trimmed.isEmpty ? secondaryTextColor : primaryTextColor)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.black.opacity(colorScheme == .dark ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func credentialEditorSheet(for kind: WeatherCredentialKind) -> some View {
        WeatherCredentialEditorView(kind: kind, text: editingCredentialText) { newValue in
            updateCredential(kind, value: newValue)
        }
    }

    private func credentialValue(for kind: WeatherCredentialKind) -> String {
        switch kind {
        case .apiHost:
            return store.config.apiHost
        case .apiKey:
            return store.config.apiKey
        }
    }

    private func updateCredential(_ kind: WeatherCredentialKind, value: String) {
        switch kind {
        case .apiHost:
            store.updateAPIHost(value)
        case .apiKey:
            store.updateAPIKey(value)
        }
    }

    private func maskedCredential(_ value: String) -> String {
        let trimmedValue = value.trimmed
        guard !trimmedValue.isEmpty else { return "未填写" }

        let characters = Array(trimmedValue)
        guard characters.count > 4 else {
            return String(characters.prefix(1)) + "****" + String(characters.suffix(1))
        }

        let visibleCount = characters.count > 10 ? 4 : 2
        let prefix = String(characters.prefix(visibleCount))
        let suffix = String(characters.suffix(visibleCount))
        let hiddenCount = max(4, min(12, characters.count - visibleCount * 2))

        // 设置页只展示脱敏值，避免 Host 和 Key 在列表中明文暴露。
        return prefix + String(repeating: "*", count: hiddenCount) + suffix
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

    private var previewImage: UIImage? {
        guard let snapshot = store.snapshot else { return nil }
        let targetSize = CGSize(width: 400, height: 600)
        return WeatherSkillRenderer.renderDisplayImage(
            snapshot: snapshot,
            template: store.config.template,
            targetSize: targetSize
        )
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

}

private struct WeatherCredentialEditorView: View {
    let kind: WeatherCredentialKind
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String

    init(kind: WeatherCredentialKind, text: String, onSave: @escaping (String) -> Void) {
        self.kind = kind
        self.onSave = onSave
        _draft = State(initialValue: text)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if kind.usesSecureInput {
                        SecureField(kind.placeholder, text: $draft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        TextField(kind.placeholder, text: $draft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } footer: {
                    Text("保存后设置页会继续以星号脱敏展示。")
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        // 只在编辑页处理明文，设置页始终展示脱敏内容。
                        onSave(draft)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct WeatherCitySelectionView: View {
    @ObservedObject var store: WeatherSkillStore
    @State private var query = ""

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Picker("城市模式", selection: Binding(
                    get: { store.config.cityMode },
                    set: { store.updateCityMode($0) }
                )) {
                    ForEach(WeatherCityMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if store.config.cityMode == .automatic {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("默认使用当前位置获取天气。")
                            .font(.system(size: 15, weight: .medium))
                        Text(store.locationStatusText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Button("刷新当前位置") {
                            Task {
                                await store.refreshWeather()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField(
                            "输入城市，如深圳、上海、北京",
                            text: Binding(
                                get: { query.isEmpty ? store.config.fixedCityQuery : query },
                                set: {
                                    query = $0
                                    store.updateFixedCityQuery($0)
                                }
                            )
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        HStack(spacing: 10) {
                            Button("搜索城市") {
                                Task {
                                    await store.searchCities(query: query)
                                }
                            }
                            .buttonStyle(.borderedProminent)

                            if store.isSearchingCities {
                                ProgressView()
                            }
                        }

                        commonCityButtons

                        if let selected = store.config.fixedLocation {
                            Text("当前城市: \(selected.displayName)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 10) {
                            ForEach(store.cityResults) { city in
                                Button {
                                    store.selectFixedCity(city)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(city.name)
                                                .font(.system(size: 16, weight: .semibold))
                                            Text(city.displayName)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if store.config.fixedLocation?.id == city.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Color(red: 0.18, green: 0.49, blue: 0.98))
                                        }
                                    }
                                    .padding(14)
                                    .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("城市管理")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var commonCityButtons: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 10)], spacing: 10) {
            ForEach(["深圳", "上海", "北京", "杭州", "广州"], id: \.self) { city in
                Button(city) {
                    query = city
                    store.updateFixedCityQuery(city)
                    Task {
                        await store.searchCities(query: city)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct WeatherFrequencyPickerView: View {
    @ObservedObject var store: WeatherSkillStore

    var body: some View {
        List {
            ForEach(WeatherUpdateFrequency.allCases) { frequency in
                Button {
                    store.updateFrequency(frequency)
                } label: {
                    HStack {
                        Text(frequency.title)
                        Spacer()
                        if store.config.updateFrequency == frequency {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(red: 0.18, green: 0.49, blue: 0.98))
                        }
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle("更新频率")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WeatherTemplatePickerView: View {
    @ObservedObject var store: WeatherSkillStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                Button {
                    store.updateTemplate(.minimalist)
                } label: {
                    HStack(spacing: 14) {
                        templatePreview(.minimalist)
                            .frame(width: 88, height: 132)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("极简版")
                                .font(.system(size: 18, weight: .semibold))
                            Text("强调时间、温度与空气质量。其余模板后续补设计。")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(red: 0.18, green: 0.49, blue: 0.98))
                    }
                    .padding(14)
                    .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
            .padding(20)
        }
        .navigationTitle("选择模板")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func templatePreview(_ template: WeatherDisplayTemplate) -> some View {
        if let snapshot = store.snapshot {
            let image = WeatherSkillRenderer.renderDisplayImage(
                snapshot: snapshot,
                template: template,
                targetSize: CGSize(width: 400, height: 600)
            )
            Image(uiImage: image)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
                .overlay(
                    Text(template.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                )
        }
    }
}

private struct WeatherDevicePickerView: View {
    @ObservedObject var store: WeatherSkillStore
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

private struct WeatherAutomationGuideView: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                automationStep(number: "1", title: "先配置天气技能", detail: "确认天气 API 已填写完成，并且“同步到设备”里已经选好目标设备。")
                automationStep(number: "2", title: "打开快捷指令 App", detail: "搜索“天气推送”或直接搜索 Tatoo!，就能看到这个快捷指令动作。")
                automationStep(number: "3", title: "添加到自动化", detail: "在个人自动化里加入“天气推送”，可绑定固定时间、到达地点等触发条件。")
                automationStep(number: "4", title: "首次验证设备在线", detail: "首次建议手动运行一次，确认设备在附近且蓝牙权限、天气配置都正常。")
            }
            .padding(20)
        }
        .navigationTitle("快捷指令说明")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func automationStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color(red: 0.18, green: 0.49, blue: 0.98), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Text(detail)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WeatherSkillSyncContext: Identifiable {
    let id = UUID()
    let displayImage: UIImage
    let transferImage: UIImage
    let device: BleDevice
}

private struct WeatherSkillSyncView: View {
    let context: WeatherSkillSyncContext
    let onSynchronized: () -> Void

    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.dismiss) private var dismiss
    @State private var didTriggerTransfer = false
    @State private var didHandleSuccess = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    if bleService.transferPhase == .succeeded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 92, weight: .medium))
                            .foregroundStyle(Color(red: 0.20, green: 0.72, blue: 0.34))

                        Text("同步成功")
                            .font(.system(size: 30, weight: .bold))

                        Text("内容已更新到 \(context.device.name)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else if case .failed = bleService.transferPhase {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 92, weight: .medium))
                            .foregroundStyle(.red)

                        Text("同步失败")
                            .font(.system(size: 30, weight: .bold))

                        Text(bleService.errorMessage ?? "设备传输失败，请稍后重试。")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    } else {
                        ZStack {
                            Circle()
                                .stroke(Color.black.opacity(0.08), lineWidth: 12)
                                .frame(width: 146, height: 146)

                            ProgressView(value: bleService.transferProgress)
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(1.6)

                            Text("\(Int(bleService.transferProgress * 100))%")
                                .font(.system(size: 30, weight: .semibold))
                                .monospacedDigit()
                        }

                        Text("正在同步到墨水屏")
                            .font(.system(size: 24, weight: .bold))

                        VStack(alignment: .leading, spacing: 12) {
                            syncStepRow(title: "连接设备", finished: true)
                            syncStepRow(title: "发送数据", finished: bleService.transferProgress >= 0.35)
                            syncStepRow(title: "刷新屏幕", finished: bleService.transferPhase == .succeeded)
                        }
                        .padding(.horizontal, 32)
                    }

                    Spacer()

                    if bleService.transferPhase == .succeeded {
                        Button("完成") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.18, green: 0.49, blue: 0.98))
                    } else if case .failed = bleService.transferPhase {
                        VStack(spacing: 10) {
                            Button("重试") {
                                startTransfer()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.18, green: 0.49, blue: 0.98))

                            Button("取消") {
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        Button("取消") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.bottom, 40)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                startTransfer()
            }
            .onChange(of: bleService.transferPhase) { _, phase in
                guard phase == .succeeded, !didHandleSuccess else { return }
                didHandleSuccess = true
                bleService.markLastTransferredImage(context.displayImage)
                onSynchronized()
            }
        }
    }

    private func startTransfer() {
        didHandleSuccess = false
        didTriggerTransfer = true
        bleService.transfer(image: context.transferImage, to: context.device)
    }

    private func syncStepRow(title: String, finished: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: finished ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(finished ? Color(red: 0.18, green: 0.49, blue: 0.98) : Color.gray)
            Text(title)
                .font(.system(size: 15, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SkillsHomeView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()
                SkillsHomeView()
                    .environmentObject(BleTransferService(forcePreviewPrompt: true))
            }
        }
    }
}
