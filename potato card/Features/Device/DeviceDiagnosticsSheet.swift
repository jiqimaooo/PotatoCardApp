import SwiftUI

struct DeviceDiagnosticsSheet: View {
    @EnvironmentObject private var bleService: BleTransferService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        deviceSummaryCard
                        backgroundShortcutCard
                        logCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("设备诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var deviceSummaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(iconFillColor)
                        .frame(width: 74, height: 88)

                    Image("ink_tatoo2")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 54, height: 76)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(activeDevice?.name ?? "未选择设备")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(1)

                    Text(deviceSubtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                statusPill(title: bleService.bluetoothState.title, systemImage: "dot.radiowaves.left.and.right")
                statusPill(title: bleService.connectionPhase.title, systemImage: "link")
            }

            if bleService.transferPhase == .preparing || bleService.transferPhase == .transferring {
                ProgressView(value: bleService.transferProgress)
                    .tint(accentColor)
                Text("\(bleService.transferPhase.title) \(Int(bleService.transferProgress * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
            }
        }
        .padding(18)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(cardStroke)
    }

    private var backgroundShortcutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("后台快捷指令")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(primaryTextColor)

                    Text("纯后台推送依赖系统时间窗口，设备已连接或可快速扫描到时更可靠。")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if let record = bleService.lastBackgroundShortcutTransfer {
                    statusPill(title: record.phase.title, systemImage: "bolt.horizontal.circle")
                }
            }

            if let record = bleService.lastBackgroundShortcutTransfer {
                VStack(alignment: .leading, spacing: 8) {
                    shortcutInfoRow(title: "目标设备", value: record.targetDeviceName)
                    shortcutInfoRow(title: "任务编号", value: String(record.jobID.prefix(8)))
                    shortcutInfoRow(title: "耗时", value: record.durationText)
                    if let lastEvent = record.lastEvent, !lastEvent.isEmpty {
                        shortcutInfoRow(title: "最近阶段", value: lastEvent)
                    }
                    if let errorMessage = record.errorMessage, !errorMessage.isEmpty {
                        shortcutInfoRow(title: "失败原因", value: errorMessage)
                    }
                }
            } else {
                Text("暂无后台快捷指令记录")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
            }
        }
        .padding(18)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(cardStroke)
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("实时日志")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(primaryTextColor)

                    Text("最近 \(bleService.diagnosticLogs.count) 条")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                }

                Spacer()

                Button("清空") {
                    bleService.clearDiagnosticLogs()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accentColor)
                .disabled(bleService.diagnosticLogs.isEmpty)
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if bleService.diagnosticLogs.isEmpty {
                            Text("暂无日志")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(secondaryTextColor)
                                .frame(maxWidth: .infinity, minHeight: 96)
                        } else {
                            ForEach(bleService.diagnosticLogs) { entry in
                                logRow(entry)
                                    .id(entry.id)
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(minHeight: 180, maxHeight: 300)
                .background(logFillColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onChange(of: bleService.diagnosticLogs.count) { _ in
                    guard let lastID = bleService.diagnosticLogs.last?.id else { return }
                    // 日志区自动滚到最新事件，方便真机联调时盯进度。
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
        .padding(18)
        .background(cardFillColor, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(cardStroke)
    }

    private func logRow(_ entry: DeviceDiagnosticLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(logLevelColor(entry.level))
                .frame(width: 7, height: 7)
                .padding(.top, 5)

            Text(entry.timeText)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(secondaryTextColor)
                .frame(width: 54, alignment: .leading)

            Text(entry.message)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(primaryTextColor.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusPill(title: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))

            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(secondaryTextColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(rowFillColor, in: Capsule())
    }

    private func shortcutInfoRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(secondaryTextColor)
                .frame(width: 58, alignment: .leading)

            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(primaryTextColor.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var activeDevice: BleDevice? {
        bleService.connectedDevice ?? bleService.selectedDevice
    }

    private var deviceSubtitle: String {
        guard let device = activeDevice else {
            return "等待扫描或连接设备"
        }

        return "\(device.profile.name) · \(device.profile.displaySize)"
    }

    private func logLevelColor(_ level: DeviceDiagnosticLogLevel) -> Color {
        switch level {
        case .info:
            return accentColor
        case .success:
            return .green
        case .warning:
            return .yellow
        case .error:
            return .red
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.07, green: 0.07, blue: 0.08) : Color(red: 0.96, green: 0.97, blue: 0.98)
    }

    private var cardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : .white
    }

    private var iconFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }

    private var rowFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.045)
    }

    private var logFillColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.26) : Color.black.opacity(0.035)
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.05), lineWidth: 1)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.88)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.52)
    }

    private var accentColor: Color {
        Color(red: 0.18, green: 0.49, blue: 0.98)
    }
}

private struct DeviceDiagnosticsSheet_Previews: PreviewProvider {
    static var previews: some View {
        DeviceDiagnosticsSheet()
            .environmentObject(BleTransferService(forcePreviewPrompt: true))
    }
}
