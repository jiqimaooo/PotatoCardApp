//
//  ContentView.swift
//  potato card
//
//  Created by wangye on 2026/4/10.
//

import SwiftUI
import UIKit

struct ContentView: View {
    private enum Tab: Hashable {
        case home
        case gallery
        case todo
        case skills
    }

    private let accentColor = Color(red: 0.18, green: 0.49, blue: 0.98)

    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Tab = .home
    @State private var loadedTabs: Set<Tab> = [.home]
    @State private var didBeginInitialAutoScan = false
    @State private var didScheduleTabPrewarm = false
    @State private var bluetoothPulse = false
    @State private var isDiagnosticsSheetPresented = false
    @State private var transferredPhotoImage: UIImage?
    @AppStorage("transferredAlbum") private var transferredAlbumName = ""
    @AppStorage("transferredPhotoPath") private var transferredPhotoPath = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            tabContent(.home) {
                homeTab
            }
                .tabItem {
                    Label("设备", systemImage: "iphone")
                }
                .tag(Tab.home)

            tabContent(.gallery) {
                galleryTab
            }
                .tabItem {
                    Label("图库", systemImage: "photo.on.rectangle")
                }
                .tag(Tab.gallery)

            tabContent(.todo) {
                todoTab
            }
                .tabItem {
                    Label("待办", systemImage: "checklist")
                }
                .tag(Tab.todo)

            tabContent(.skills) {
                skillsTab
            }
                .tabItem {
                    Label("skills", systemImage: "square.grid.2x2")
                }
                .tag(Tab.skills)
        }
        .tint(accentColor)
        .overlay(alignment: .bottom) {
            proximityConnectionCard
        }
        .sheet(isPresented: $isDiagnosticsSheetPresented) {
            DeviceDiagnosticsSheet()
                .environmentObject(bleService)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            beginInitialAutoScanIfNeeded()
            loadTransferredPhotoImage()
            scheduleSafeTabPrewarmIfNeeded()
        }
        .onChange(of: selectedTab) { tab in
            loadedTabs.insert(tab)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                bleService.handleSceneBecameActive()
            case .background:
                bleService.handleSceneEnteredBackground()
            default:
                break
            }
        }
        .onChange(of: transferredPhotoPath) { _ in
            loadTransferredPhotoImage()
        }
    }

    @ViewBuilder
    private func tabContent<Content: View>(_ tab: Tab, @ViewBuilder content: () -> Content) -> some View {
        if loadedTabs.contains(tab) || selectedTab == tab {
            content()
        } else {
            Color.clear
        }
    }

    private var homeTab: some View {
        NavigationStack {
            ZStack {
                backgroundColor
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        headerView
                        heroCard
                            .padding(.top, 38)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 40)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var galleryTab: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                backgroundColor
                    .ignoresSafeArea()

                GalleryView { imageData in
                    persistTransferredPhoto(imageData)
                    selectedTab = .home
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var todoTab: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                backgroundColor
                    .ignoresSafeArea()

                TodoView()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var skillsTab: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                backgroundColor
                    .ignoresSafeArea()

                SkillsHomeView { album in
                    transferredAlbumName = album
                    transferredPhotoPath = ""
                    selectedTab = .home
                }
                    .padding(.top, 0)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Potato Card")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(primaryTextColor)

            Text("记录瞬间，收藏热爱，展示属于你的美好")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroCard: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(cardFillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(colorScheme == .dark ? 0.32 : 0.52))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .stroke(cardStrokeColor, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.06), radius: 24, x: 0, y: 14)

                ZStack {
                    if let transferredDeviceImage {
                        transferredDeviceImage
                            .resizable()
                            .scaledToFill()
                            .frame(width: 197, height: 295)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .offset(y: -21)
                    }

                    Image("ink_tatoo2")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 372)
                }
                .offset(y: -25)

                VStack {
                    Spacer()

                    HStack(spacing: 12) {
                        bluetoothStatusIcon
                        diagnosticsSettingsButton
                        batteryStatusPill
                    }
                    .padding(.bottom, 25)
                }
            }
            .frame(height: 500)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var proximityConnectionCard: some View {
        if let device = bleService.proximityPromptDevice {
            VStack {
                Spacer()

                VStack(spacing: 18) {
                    Text("发现新设备")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(promptTitleColor)

                    ZStack {
                        ZStack {
                            Image("ink_tatoo2")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 160, height: 200)

                            Image("tatoo1")
                                .resizable()
                                .scaledToFill()
                                .frame(width: 106, height: 158)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .offset(y: -14)
                        }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 6)
                    }
                    .frame(height: 206)

                    VStack(spacing: 8) {
                        Button {
                            bleService.connect(device)
                        } label: {
                            HStack(spacing: 8) {
                                if bleService.connectionPhase == .connecting {
                                    ProgressView()
                                        .controlSize(.small)
                                } else if bleService.connectionPhase == .connected && bleService.connectedDevice?.id == device.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                }

                                Text(connectionButtonTitle(for: device))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .frame(width: 132, height: 28)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(bleService.connectionPhase == .connecting || bleService.connectedDevice?.id == device.id)

                        Button {
                            bleService.postponeProximityPrompt()
                        } label: {
                            Text("稍后连接")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(laterButtonTextColor)
                                .frame(width: 132, height: 28)
                        }
                        .buttonStyle(.bordered)
                        .tint(laterButtonTintColor)
                        .disabled(bleService.connectionPhase == .connecting)
                    }
                }
                .frame(minHeight: 306)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 22)
                .background(promptCardFillColor, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(cardStrokeColor, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.14), radius: 28, x: 0, y: 14)
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .animation(.spring(response: 0.36, dampingFraction: 0.86), value: bleService.proximityPromptDevice?.id)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func statusPill(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))

            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(secondaryTextColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(statusPillFillColor, in: Capsule())
        .overlay(
            Capsule()
                .stroke(statusPillStrokeColor, lineWidth: 1)
        )
    }

    private var bluetoothStatusIcon: some View {
        let isConnecting = bleService.connectionPhase == .connecting
        let isConnected = bleService.connectedDevice != nil || bleService.connectionPhase == .connected
        let iconColor = (isConnected || isConnecting) ? accentColor : inactiveBluetoothIconColor

        return ZStack {
            Capsule()
                .fill(statusPillFillColor)
                .frame(width: 44, height: 34)
                .overlay(
                    Capsule()
                        .stroke(statusPillStrokeColor, lineWidth: 1)
                )

            if isConnecting {
                Capsule()
                    .stroke(accentColor.opacity(0.36), lineWidth: 1.5)
                    .frame(width: 44, height: 34)
                    .scaleEffect(bluetoothPulse ? 1.24 : 0.92)
                    .opacity(bluetoothPulse ? 0 : 1)
                    .animation(.easeOut(duration: 0.9).repeatForever(autoreverses: false), value: bluetoothPulse)
                    .onAppear {
                        bluetoothPulse = false
                        DispatchQueue.main.async {
                            bluetoothPulse = true
                        }
                    }
            }

            Image("bluetooth_generated")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(iconColor)
                .frame(width: 16, height: 16)
        }
        .onChange(of: isConnecting) { newValue in
            bluetoothPulse = newValue
        }
    }

    private var diagnosticsSettingsButton: some View {
        Button {
            isDiagnosticsSheetPresented = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(secondaryTextColor)
                .frame(width: 34, height: 34)
                .background(statusPillFillColor, in: Circle())
                .overlay(
                    Circle()
                        .stroke(statusPillStrokeColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("设备设置")
    }

    private var batteryStatusPill: some View {
        let percent = bleService.displayedBatteryPercent
        let color = batteryLevelColor(for: percent)

        return HStack(spacing: 5) {
            BatteryLevelIcon(percent: percent, color: color)
                .frame(width: 22, height: 12)

            Text(percent.map { "\(min(100, max(0, $0)))%" } ?? "--%")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(secondaryTextColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(statusPillFillColor, in: Capsule())
        .overlay(
            Capsule()
                .stroke(statusPillStrokeColor, lineWidth: 1)
        )
        .accessibilityLabel(percent.map { "设备电量 \(min(100, max(0, $0)))%" } ?? "设备电量未知")
    }

    private func batteryLevelColor(for percent: Int?) -> Color {
        guard let percent else {
            return secondaryTextColor.opacity(0.48)
        }

        switch percent {
        case 0..<20:
            return .red
        case 20..<50:
            return .yellow
        default:
            return .green
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.07, green: 0.07, blue: 0.08) : .white
    }

    private var transferredAlbum: String? {
        transferredAlbumName.isEmpty ? nil : transferredAlbumName
    }

    private var transferredDeviceImage: Image? {
        if let lastTransferredImage = bleService.lastTransferredImage {
            return Image(uiImage: lastTransferredImage)
        }

        if let transferredAlbum {
            return Image(transferredAlbum)
        }

        guard let transferredPhotoImage else { return nil }
        return Image(uiImage: transferredPhotoImage)
    }

    private func beginInitialAutoScanIfNeeded() {
        guard !didBeginInitialAutoScan else { return }
        didBeginInitialAutoScan = true

        // 首帧先展示出来，再启动 SDK 蓝牙工作，避免更新后首次打开卡住。
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            bleService.beginForegroundAutoScan()
        }
    }

    private func scheduleSafeTabPrewarmIfNeeded() {
        guard !didScheduleTabPrewarm else { return }
        didScheduleTabPrewarm = true

        Task { @MainActor in
            // 分批加载不触发定位/网络的页面，避免用户第一次切换时集中解码资源。
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            loadedTabs.insert(.gallery)

            try? await Task.sleep(nanoseconds: 500_000_000)
            loadedTabs.insert(.todo)
        }
    }

    private func persistTransferredPhoto(_ imageData: Data) {
        guard let fileURL = transferredPhotoURL else { return }

        do {
            try imageData.write(to: fileURL, options: .atomic)
            transferredPhotoPath = fileURL.path
            transferredPhotoImage = UIImage(data: imageData)
            transferredAlbumName = ""
        } catch {
            // Keep the current device image if writing the new one fails.
        }
    }

    private func loadTransferredPhotoImage() {
        guard !transferredPhotoPath.isEmpty else {
            transferredPhotoImage = nil
            return
        }

        let photoPath = transferredPhotoPath
        Task {
            // 照片可能很大，放到后台解码，避免 body 计算时同步读磁盘。
            let image = await Task.detached(priority: .utility) {
                guard
                    let data = try? Data(contentsOf: URL(fileURLWithPath: photoPath)),
                    let uiImage = UIImage(data: data)
                else {
                    return nil as UIImage?
                }

                return uiImage
            }.value

            await MainActor.run {
                guard transferredPhotoPath == photoPath else { return }
                transferredPhotoImage = image
            }
        }
    }

    private var transferredPhotoURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("transferred-device-photo.jpg")
    }

    private var cardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.74)
    }

    private var cardStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.72)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.92)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.72)
    }

    private var promptTitleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.86) : Color(red: 0.18, green: 0.18, blue: 0.20)
    }

    private var inactiveBluetoothIconColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.82) : Color.black.opacity(0.82)
    }

    private var promptCardFillColor: Color {
        colorScheme == .dark ? Color(red: 0.13, green: 0.13, blue: 0.15) : .white
    }

    private var laterButtonTintColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.12)
    }

    private var laterButtonTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.90) : .black
    }

    private var statusPillFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.82)
    }

    private var statusPillStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.85)
    }

    private func connectionButtonTitle(for device: BleDevice) -> String {
        if bleService.connectedDevice?.id == device.id {
            return "已连接"
        }

        return bleService.connectionPhase == .connecting ? "连接中" : "连接设备"
    }

}

private struct BatteryLevelIcon: View {
    let percent: Int?
    let color: Color

    private var clampedPercent: Int? {
        percent.map { min(100, max(0, $0)) }
    }

    private var fillRatio: CGFloat {
        CGFloat(clampedPercent ?? 0) / 100
    }

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.6, style: .continuous)
                    .stroke(color.opacity(clampedPercent == nil ? 0.55 : 1), lineWidth: 1.4)

                GeometryReader { proxy in
                    let inset: CGFloat = 2
                    let fillWidth = max((proxy.size.width - inset * 2) * fillRatio, 0)
                    let fillHeight = max(proxy.size.height - inset * 2, 0)

                    // 按内边距后的可用区域填充，满电时左右留白保持一致。
                    RoundedRectangle(cornerRadius: 1.8, style: .continuous)
                        .fill(color)
                        .frame(width: fillWidth, height: fillHeight)
                        .offset(x: inset, y: inset)
                }
            }

            RoundedRectangle(cornerRadius: 0.8, style: .continuous)
                .fill(color.opacity(clampedPercent == nil ? 0.55 : 1))
                .frame(width: 2.2, height: 5.5)
        }
    }
}

private struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(BleTransferService(forcePreviewPrompt: true))
    }
}
