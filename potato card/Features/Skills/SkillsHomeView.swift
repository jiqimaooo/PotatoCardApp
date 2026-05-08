import SwiftUI
import UIKit

struct SkillsHomeView: View {
    let onAlbumTransferToDevice: (String) -> Void

    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var weatherStore = WeatherSkillStore()
    @State private var activeSyncContext: WeatherSkillSyncContext?
    @State private var didHandleActiveSyncSuccess = false

    init(onAlbumTransferToDevice: @escaping (String) -> Void = { _ in }) {
        self.onAlbumTransferToDevice = onAlbumTransferToDevice
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
                weatherSkillCard
                albumSkillCard
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
        .onChange(of: bleService.connectedDevice?.id) { _ in
            backfillTargetDeviceSelectionIfNeeded()
        }
        .onChange(of: bleService.selectedDevice?.id) { _ in
            backfillTargetDeviceSelectionIfNeeded()
        }
        .onChange(of: bleService.transferPhase) { phase in
            handleTransferPhaseChange(phase)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("技能")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(primaryTextColor)

            Text("管理你的技能")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        startWeatherSync()
                    } label: {
                        syncButtonLabel(height: 38, cornerRadius: 11, fontSize: 14)
                    }
                    .buttonStyle(.plain)
                    .opacity(!canStartWeatherSync && !isWeatherSyncing ? 0.45 : 1)
                    .disabled(!canStartWeatherSync || isWeatherSyncing)

                    NavigationLink {
                        WeatherSkillDetailView(
                            store: weatherStore,
                            onSyncRequested: {
                                startWeatherSync()
                            },
                            isSyncing: isWeatherSyncing,
                            syncProgress: bleService.transferProgress
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
        .frame(height: skillCardHeight)
    }

    private var albumSkillCard: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.96, green: 0.31, blue: 0.45),
                                    Color(red: 0.38, green: 0.20, blue: 0.86)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)
                        .overlay(
                            Image(systemName: "music.note.list")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.white)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("专辑")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(primaryTextColor)

                        Text("把喜欢的专辑封面推到土豆片")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(secondaryTextColor)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)
                }

                Text("\(AlbumCatalog.allAlbums.count) 张封面 · 周杰伦 / 孙燕姿")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(primaryTextColor.opacity(0.78))
                    .lineLimit(1)

                Text(activeDevice == nil ? "连接设备后可直接传输专辑封面" : "当前设备：\(activeDevice?.name ?? "已连接")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    NavigationLink {
                        AlbumSkillDetailView(onTransferToDevice: onAlbumTransferToDevice)
                            .environmentObject(bleService)
                    } label: {
                        Text("打开")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(accentColor, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    // 保留和天气卡片右侧设置按钮一致的占位宽度，避免“打开”按钮变长。
                    Color.clear
                        .frame(width: 84, height: 38)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            albumPreview
                .frame(width: 88, height: 132)
        }
        .padding(14)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cardStrokeColor, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.035), radius: 10, x: 0, y: 4)
        .frame(height: skillCardHeight)
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

    private var albumPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.white)
                .shadow(color: Color.black.opacity(0.035), radius: 6, x: 0, y: 3)

            // 专辑模块复用设备屏幕比例，用封面叠层表达“封面推送”。
            ZStack {
                ForEach(Array(AlbumCatalog.featuredAlbums.enumerated()), id: \.offset) { index, album in
                    Image(album)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.white.opacity(0.82), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.14), radius: 5, x: 0, y: 3)
                        .rotationEffect(.degrees(albumPreviewRotations[index]))
                        .offset(x: albumPreviewOffsets[index].width, y: albumPreviewOffsets[index].height)
                }
            }
            .frame(width: 78, height: 118)

            VStack {
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.system(size: 8, weight: .bold))
                    Text("ALBUM")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.46))
                .padding(.bottom, 8)
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

    private var isWeatherSyncing: Bool {
        bleService.transferPhase == .preparing || bleService.transferPhase == .transferring
    }

    private var canStartWeatherSync: Bool {
        weatherStore.snapshot != nil && (selectedTargetDevice ?? activeDevice) != nil
    }

    @ViewBuilder
    private func syncButtonLabel(height: CGFloat, cornerRadius: CGFloat, fontSize: CGFloat) -> some View {
        let progress = min(max(bleService.transferProgress, 0), 1)
        let showsProgress = isWeatherSyncing && progress >= 0.03

        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isWeatherSyncing ? accentColor.opacity(0.28) : accentColor)

            if showsProgress {
                GeometryReader { proxy in
                    // 传输中复用按钮自身空间做进度条，避免额外弹层打断操作流。
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(accentColor)
                        .frame(width: min(proxy.size.width, max(height, proxy.size.width * progress)))
                }
                .allowsHitTesting(false)
            }

            Text(isWeatherSyncing ? "同步中 \(Int(progress * 100))%" : "立即同步")
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func startWeatherSync() {
        guard !isWeatherSyncing, let context = makeSyncContext() else { return }
        activeSyncContext = context
        didHandleActiveSyncSuccess = false
        // 前台“立即同步”也要显式透传天气模块自己的算法，不能回落到全局算法。
        bleService.transfer(
            image: context.transferImage,
            displayImage: context.displayImage,
            to: context.device,
            algorithm: weatherStore.config.imageAlgorithm
        )
    }

    private func handleTransferPhaseChange(_ phase: TransferPhase) {
        guard let context = activeSyncContext else { return }

        switch phase {
        case .succeeded:
            guard !didHandleActiveSyncSuccess else { return }
            didHandleActiveSyncSuccess = true
            bleService.markLastTransferredImage(context.displayImage)
            weatherStore.markSynced()
            activeSyncContext = nil
        case .failed:
            didHandleActiveSyncSuccess = false
            activeSyncContext = nil
        default:
            break
        }
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

    private var skillCardHeight: CGFloat {
        160
    }

    private var albumPreviewRotations: [Double] {
        [-9, 5, 12]
    }

    private var albumPreviewOffsets: [CGSize] {
        [
            CGSize(width: -14, height: -24),
            CGSize(width: 12, height: -4),
            CGSize(width: 0, height: 24)
        ]
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

private struct AlbumSkillDetailView: View {
    let onTransferToDevice: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            pageBackgroundColor
                .ignoresSafeArea()

            AlbumView(onTransferToDevice: onTransferToDevice)
                .padding(.horizontal, 24)
                .padding(.top, 22)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var pageBackgroundColor: Color {
        colorScheme == .dark ? Color.black : Color(red: 0.98, green: 0.98, blue: 0.98)
    }
}

private enum WeatherCredentialKind: String {
    case apiHost
    case apiKey

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
}

private struct WeatherSkillDetailView: View {
    @ObservedObject var store: WeatherSkillStore
    let onSyncRequested: () -> Void
    let isSyncing: Bool
    let syncProgress: Double

    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.colorScheme) private var colorScheme
    @State private var isAPISectionExpanded = false
    @State private var isAPIHostVisible = false
    @State private var isAPIKeyVisible = false

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
            detailNavigationRow(title: "显示模板", value: store.config.template.title) {
                WeatherTemplatePickerView(store: store)
            }
            dividerRow
            detailNavigationRow(title: "图像算法", value: store.config.imageAlgorithm.title) {
                WeatherImageAlgorithmPickerView(store: store)
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
            Button {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                    isAPISectionExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Text("和风天气配置")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(primaryTextColor)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(secondaryTextColor)
                        .rotationEffect(.degrees(isAPISectionExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isAPISectionExpanded {
                Text("请配置和风天气 API Host 和 API Key，注意数据保护")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                VStack(spacing: 12) {
                    credentialField(
                        kind: .apiHost,
                        text: Binding(
                            get: { store.config.apiHost },
                            set: { store.updateAPIHost($0) }
                        ),
                        isVisible: $isAPIHostVisible
                    )
                    credentialField(
                        kind: .apiKey,
                        text: Binding(
                            get: { store.config.apiKey },
                            set: { store.updateAPIKey($0) }
                        ),
                        isVisible: $isAPIKeyVisible
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
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
            Button {
                onSyncRequested()
            } label: {
                syncButtonLabel
            }
            .buttonStyle(.plain)
            .opacity(previewImage == nil || selectedDevice == nil ? 0.45 : 1)
            .disabled(previewImage == nil || selectedDevice == nil || isSyncing)

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
            .disabled(isWeatherRefreshing)
        }
    }

    private var isWeatherRefreshing: Bool {
        // 刷新中禁用按钮，避免重复触发天气请求。
        store.loadState == .locating || store.loadState == .loading
    }

    private var syncButtonLabel: some View {
        let progress = min(max(syncProgress, 0), 1)
        let accentColor = Color(red: 0.18, green: 0.49, blue: 0.98)
        let showsProgress = isSyncing && progress >= 0.03

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSyncing ? accentColor.opacity(0.28) : accentColor)

            if showsProgress {
                GeometryReader { proxy in
                    // 详情页也直接在按钮内展示进度，保持按钮尺寸稳定。
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accentColor)
                        .frame(width: min(proxy.size.width, max(48, proxy.size.width * progress)))
                }
                .allowsHitTesting(false)
            }

            Text(isSyncing ? "同步中 \(Int(progress * 100))%" : "立即同步")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func credentialField(
        kind: WeatherCredentialKind,
        text: Binding<String>,
        isVisible: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(primaryTextColor)

            HStack(spacing: 8) {
                Group {
                    if isVisible.wrappedValue {
                        TextField(kind.placeholder, text: text)
                    } else {
                        // 默认隐藏敏感配置，但仍然直接编辑绑定的真实值。
                        SecureField(kind.placeholder, text: text)
                    }
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(primaryTextColor)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button {
                    isVisible.wrappedValue.toggle()
                } label: {
                    Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isVisible.wrappedValue ? "隐藏\(kind.title)" : "显示\(kind.title)")
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 44)
            .background(Color.black.opacity(colorScheme == .dark ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
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
                ForEach(WeatherDisplayTemplate.allCases) { template in
                    Button {
                        store.updateTemplate(template)
                    } label: {
                        HStack(spacing: 14) {
                            templatePreview(template)
                                .frame(width: 88, height: 132)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(template.title)
                                    .font(.system(size: 18, weight: .semibold))
                            }

                            Spacer()

                            if store.config.template == template {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(red: 0.18, green: 0.49, blue: 0.98))
                            }
                        }
                        .padding(14)
                        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
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

private struct WeatherImageAlgorithmPickerView: View {
    @ObservedObject var store: WeatherSkillStore

    var body: some View {
        List {
            Section {
                Text("默认 Bayer 8x8，效果更好，此处仅对天气模块生效")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(EInkDitherAlgorithm.allCases) { algorithm in
                    Button {
                        store.updateImageAlgorithm(algorithm)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(algorithm.title)
                                Text(algorithm.subtitle)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if store.config.imageAlgorithm == algorithm {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(red: 0.18, green: 0.49, blue: 0.98))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("图像算法")
        .navigationBarTitleDisplayMode(.inline)
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

private struct WeatherSkillSyncContext {
    let displayImage: UIImage
    let transferImage: UIImage
    let device: BleDevice
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
