import Combine
import CoreBluetooth
import Foundation
import OSLog
import UIKit

enum BlePowerState: Equatable {
    case poweredOff
    case poweredOn
    case unauthorized
    case unknown
    case unsupported
    case reset

    init(sdkState: Int) {
        switch sdkState {
        case 0:
            self = .poweredOff
        case 1:
            self = .poweredOn
        case 2:
            self = .unauthorized
        case 4:
            self = .unsupported
        case 5:
            self = .reset
        default:
            self = .unknown
        }
    }

    var title: String {
        switch self {
        case .poweredOff:
            return "蓝牙已关闭"
        case .poweredOn:
            return "蓝牙可用"
        case .unauthorized:
            return "未授权蓝牙"
        case .unknown:
            return "蓝牙状态未知"
        case .unsupported:
            return "不支持蓝牙"
        case .reset:
            return "蓝牙服务重置"
        }
    }

    var canScan: Bool {
        self == .poweredOn
    }
}

enum TransferPhase: Equatable {
    case idle
    case preparing
    case transferring
    case succeeded
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            return "未开始"
        case .preparing:
            return "准备传输"
        case .transferring:
            return "传输中"
        case .succeeded:
            return "传输成功"
        case .failed(let message):
            return message
        }
    }
}

enum BleConnectionPhase: Equatable {
    case idle
    case connecting
    case connected

    var title: String {
        switch self {
        case .idle:
            return "未连接"
        case .connecting:
            return "连接中"
        case .connected:
            return "已连接"
        }
    }
}

enum BatteryDisplayState: Equatable {
    case cached
    case live
    case empty
}

enum DeviceDiagnosticLogLevel: String, Codable, Equatable {
    case info
    case success
    case warning
    case error
}

struct DeviceDiagnosticLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let level: DeviceDiagnosticLogLevel
    let message: String

    var timeText: String {
        Self.timeFormatter.string(from: timestamp)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

enum BackgroundShortcutTransferPhase: String, Codable, Equatable {
    case preparing
    case scanning
    case transferring
    case succeeded
    case failed

    var title: String {
        switch self {
        case .preparing:
            return "准备后台推送"
        case .scanning:
            return "后台扫描设备"
        case .transferring:
            return "后台传输中"
        case .succeeded:
            return "后台推送成功"
        case .failed:
            return "后台推送失败"
        }
    }
}

struct BackgroundShortcutTransferRecord: Codable, Equatable {
    let jobID: String
    let targetDeviceID: String
    let targetDeviceName: String
    var phase: BackgroundShortcutTransferPhase
    var lastEvent: String?
    let startedAt: Date
    var finishedAt: Date?
    var errorMessage: String?

    var durationText: String {
        let endDate = finishedAt ?? Date()
        let seconds = max(0, Int(endDate.timeIntervalSince(startedAt).rounded()))
        return "\(seconds)s"
    }
}

enum BleTransferError: LocalizedError {
    case bluetoothUnavailable(String)
    case transferBusy
    case deviceNotReady
    case deviceInfoInvalid
    case imageInvalid
    case deviceNotFound(String)
    case transferFailed(String)
    case transferTimedOut
    case bluetoothReadyTimedOut
    case backgroundTimeExpired

    var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable(let message):
            return message
        case .transferBusy:
            return "当前已有传输任务在进行中，请稍后再试。"
        case .deviceNotReady:
            return "目标设备信息不完整，请重新选择同步设备。"
        case .deviceInfoInvalid:
            return "设备信息异常，请重新连接设备。"
        case .imageInvalid:
            return "图片生成异常，请重新选择图片。"
        case .deviceNotFound(let name):
            return "没有扫到设备 \(name)。请确保设备在附近、已开机且未休眠；后台推送可能需要重试一次。"
        case .transferFailed(let message):
            return message
        case .transferTimedOut:
            return "设备传输超时，请重试。"
        case .bluetoothReadyTimedOut:
            return "蓝牙状态初始化超时，请确认蓝牙已开启后重试。"
        case .backgroundTimeExpired:
            return "系统后台运行时间已结束，本次天气推送未完成。纯后台推送只在设备已连接或可快速扫描到时可靠。"
        }
    }
}

private enum BleTransferPresentationMode {
    case interactive
    case backgroundShortcut
}

private enum BackgroundShortcutReturnPolicy {
    case waitForCompletion
    case returnAfterTransferStarted
}

private struct BleTransferPreflight {
    let imageDataSize: Int
    let serviceUUID: String
    let controlCharacteristicUUID: String
    let writeCharacteristicUUID: String
}

private enum BleDiagnosticsStorage {
    static let ditherAlgorithmKey = "selectedEInkDitherAlgorithm"
    static let backgroundShortcutTransferKey = "lastBackgroundShortcutTransferRecord"
    static let batteryCacheKey = "deviceBatteryCacheByID"
    static let lastBatteryDeviceIDKey = "lastBatteryDeviceID"
    static let maxLogCount = 120
}

private struct DeviceBatterySnapshot: Codable, Equatable {
    let deviceID: String
    let percent: Int
    let voltage: Double?
    let updatedAt: Date
}

private enum DeviceBatteryCacheStore {
    static func load() -> [String: DeviceBatterySnapshot] {
        guard let data = UserDefaults.standard.data(forKey: BleDiagnosticsStorage.batteryCacheKey),
              let snapshots = try? JSONDecoder().decode([String: DeviceBatterySnapshot].self, from: data) else {
            return [:]
        }
        return snapshots
    }

    static func save(_ snapshots: [String: DeviceBatterySnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults.standard.set(data, forKey: BleDiagnosticsStorage.batteryCacheKey)
    }

    static var lastDeviceID: String? {
        get {
            UserDefaults.standard.string(forKey: BleDiagnosticsStorage.lastBatteryDeviceIDKey)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: BleDiagnosticsStorage.lastBatteryDeviceIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: BleDiagnosticsStorage.lastBatteryDeviceIDKey)
            }
        }
    }
}

// SDK 回调会把原始设备字典从后台线程带回主线程，这里用一个受控的桥接盒子收口并发边界。
private final class BlePayloadBox: @unchecked Sendable {
    nonisolated(unsafe) let payload: [AnyHashable: Any]

    nonisolated init(payload: [AnyHashable: Any]) {
        self.payload = payload
    }
}

// 系统过期回调可能不在主线程，使用小盒子保证后台任务只结束一次。
private final class BleBackgroundTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var taskID: UIBackgroundTaskIdentifier = .invalid

    func set(_ id: UIBackgroundTaskIdentifier) {
        lock.lock()
        taskID = id
        lock.unlock()
    }

    func end() {
        lock.lock()
        let id = taskID
        taskID = .invalid
        lock.unlock()

        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
    }
}

#if targetEnvironment(simulator)
@MainActor
final class BleTransferService: ObservableObject {
    private static let rememberedDeviceIDsKey = "rememberedProximityDeviceIDs"
    static let shared = BleTransferService()
    private let logger = Logger(subsystem: "com.xiaogousi.online.potato-card", category: "WeatherShortcut")

    @Published private(set) var bluetoothState: BlePowerState = .poweredOn
    @Published private(set) var devices: [BleDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var connectionPhase: BleConnectionPhase = .idle
    @Published private(set) var connectedDevice: BleDevice?
    @Published private(set) var proximityPromptDevice: BleDevice?
    @Published private(set) var rememberedDeviceIDs: Set<String>
    @Published private(set) var transferPhase: TransferPhase = .idle
    @Published private(set) var transferProgress: Double = 0
    @Published private(set) var currentBlock: Int = 0
    @Published private(set) var currentAddress = ""
    @Published private(set) var errorMessage: String?
    @Published var selectedDevice: BleDevice?
    @Published private(set) var lastTransferredImage: UIImage?
    @Published private(set) var ditherAlgorithm: EInkDitherAlgorithm = .floydSteinberg
    @Published private(set) var activeTransferAlgorithm: EInkDitherAlgorithm?
    @Published private(set) var diagnosticLogs: [DeviceDiagnosticLogEntry] = []
    @Published private(set) var lastBackgroundShortcutTransfer: BackgroundShortcutTransferRecord?
    @Published private(set) var displayedBatteryPercent: Int?
    @Published private(set) var batteryDisplayState: BatteryDisplayState = .empty
    // “正在同步”的发起方标识符。天气 / 健康 等技能在发起传输前调用 beginSync(source:)，
    // 传输结束后调用 endSync(source:)。UI 层按 "source == 自己" 决定哪个按钮走进度动画。
    @Published private(set) var currentSyncSource: String?
    private var wantsForegroundAutoScan = false
    private var lastBatteryByDeviceID: [String: DeviceBatterySnapshot]
    private var batteryRefreshTimeoutTask: Task<Void, Never>?
    private var batteryRefreshGeneration = 0
    private let transferredImageStore = TransferredDeviceImageStore()
    private let liveTransferActivity = LiveTransferActivityController()
    private var transferBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var transferPresentationMode: BleTransferPresentationMode = .interactive
    private var isAppInForeground = true
    private var automatedPushContinuation: CheckedContinuation<BleDevice, Error>?
    private var automatedTargetDeviceID: String?
    private var automatedMatchedDevice: BleDevice?
    private var automatedPushImage: UIImage?
    private var automatedPushDisplayImage: UIImage?
    private var automatedReturnPolicy: BackgroundShortcutReturnPolicy = .waitForCompletion
    private var activeTransferDisplayImage: UIImage?

    init(forcePreviewPrompt: Bool = false) {
        rememberedDeviceIDs = Set(UserDefaults.standard.stringArray(forKey: Self.rememberedDeviceIDsKey) ?? [])
        lastBatteryByDeviceID = DeviceBatteryCacheStore.load()
        if let savedAlgorithm = UserDefaults.standard.string(forKey: BleDiagnosticsStorage.ditherAlgorithmKey),
           let algorithm = EInkDitherAlgorithm(rawValue: savedAlgorithm) {
            ditherAlgorithm = algorithm
        }
        lastBackgroundShortcutTransfer = Self.loadBackgroundShortcutTransferRecord()
        lastTransferredImage = transferredImageStore.loadLatestImage()
        devices = [
            BleDevice(rawDevice: [
                "name": "NEMR92957953",
                "address": "PREVIEW-DEVICE",
                "power": 32
            ])
        ]
        selectedDevice = devices.first
        appendDiagnosticLog("模拟器调试会话已启动，算法：\(ditherAlgorithm.title)")
        restoreDisplayedBatteryFromCache(for: selectedDevice)
        updateBatteryDisplay(from: selectedDevice, source: .live)
        if forcePreviewPrompt {
            proximityPromptDevice = devices.first
        }
    }

    func beginForegroundAutoScan() {
        guard !isTransferInProgress else { return }
        wantsForegroundAutoScan = true
        appendDiagnosticLog("请求前台自动扫描")
        guard bluetoothState.canScan else { return }
        startScan()
    }

    func startScan() {
        guard !isTransferInProgress else { return }
        errorMessage = nil
        isScanning = true
        appendDiagnosticLog("开始扫描附近设备")
        beginBatteryRefreshWindow()
        presentPromptIfNeeded(for: devices.first)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.isScanning = false
            if self.devices.isEmpty {
                self.devices = [
                    BleDevice(rawDevice: [
                        "name": "NEMR92957953",
                        "address": "PREVIEW-DEVICE",
                        "power": 32
                    ])
                ]
                self.selectedDevice = self.devices.first
            }
            if let device = self.devices.first {
                self.updateBatteryDisplay(from: device, source: .live)
                self.appendDiagnosticLog("发现设备：\(device.name) · \(device.profile.displaySize)")
            }
            self.presentPromptIfNeeded(for: self.devices.first)
        }
    }

    func stopScan() {
        wantsForegroundAutoScan = false
        isScanning = false
        appendDiagnosticLog("停止扫描")
    }

    func handleSceneBecameActive() {
        isAppInForeground = true
        endLiveTransferActivityIfNeeded(finalPhaseTitle: transferPhase.title)
        guard !isTransferInProgress else { return }
        beginForegroundAutoScan()
    }

    func handleSceneEnteredBackground() {
        isAppInForeground = false
        wantsForegroundAutoScan = false
        guard !isTransferInProgress else {
            startLiveTransferActivityIfNeeded()
            return
        }
        stopScan()
    }

    func select(_ device: BleDevice) {
        selectedDevice = device
        appendDiagnosticLog("选择设备：\(device.name)")
        restoreDisplayedBatteryFromCache(for: device)
        updateBatteryDisplay(from: device, source: .live)
        syncLastTransferredImage(for: device)
    }

    func connect(_ device: BleDevice) {
        stopScan()
        selectedDevice = device
        connectionPhase = .connecting
        restoreDisplayedBatteryFromCache(for: device)
        appendDiagnosticLog("开始连接设备：\(device.name)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.connectedDevice = device
            self.selectedDevice = device
            self.connectionPhase = .connected
            self.rememberDevice(device)
            self.updateBatteryDisplay(from: device, source: .live)
            self.syncLastTransferredImage(for: device)
            self.appendDiagnosticLog("设备已连接：\(device.name)", level: .success)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self else { return }
                if self.proximityPromptDevice?.id == device.id {
                    self.proximityPromptDevice = nil
                }
            }
        }
    }

    func dismissProximityPrompt() {
        postponeProximityPrompt()
    }

    func postponeProximityPrompt() {
        proximityPromptDevice = nil
        appendDiagnosticLog("稍后连接当前设备")
        if connectionPhase != .connected {
            connectionPhase = .idle
        }
    }

    // 同步发起方标识符。同一时间只可能有一个 source 在同步，UI 层据此决定谁的按钮走动画。
    func beginSync(source: String) {
        currentSyncSource = source
    }

    func endSync(source: String) {
        if currentSyncSource == source {
            currentSyncSource = nil
        }
    }

    func transfer(image: UIImage, displayImage: UIImage? = nil, to device: BleDevice, algorithm: EInkDitherAlgorithm? = nil) {
        let transferAlgorithm = algorithm ?? ditherAlgorithm
        selectedDevice = device
        currentAddress = device.address
        transferPhase = .transferring
        transferProgress = 0.35
        activeTransferAlgorithm = transferAlgorithm
        activeTransferDisplayImage = displayImage
        appendDiagnosticLog("开始传输：\(device.name)，算法：\(transferAlgorithm.title)")
        appendDiagnosticLog("传输进度：35%")
        beginTransferAuxiliaryWorkIfNeeded(for: device.name)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.transferProgress = 1
            self.transferPhase = .succeeded
            if let displayImage = self.activeTransferDisplayImage {
                self.markLastTransferredImage(displayImage, for: device.id)
            }
            self.activeTransferDisplayImage = nil
            self.appendDiagnosticLog("传输成功：\(device.name)", level: .success)
            self.endTransferAuxiliaryWorkIfNeeded(finalPhaseTitle: self.transferPhase.title)
            self.finishAutomatedPush(with: .success(device))
        }
    }

    func setDitherAlgorithm(_ algorithm: EInkDitherAlgorithm) {
        guard ditherAlgorithm != algorithm else { return }
        ditherAlgorithm = algorithm
        UserDefaults.standard.set(algorithm.rawValue, forKey: BleDiagnosticsStorage.ditherAlgorithmKey)
        appendDiagnosticLog("切换图像算法：\(algorithm.title)")
    }

    func clearDiagnosticLogs() {
        diagnosticLogs.removeAll()
    }

    func pushWeatherImage(
        _ image: UIImage,
        displayImage: UIImage? = nil,
        toTargetDeviceSnapshot snapshot: WeatherTargetDeviceSnapshot,
        algorithm: EInkDitherAlgorithm? = nil,
        returnAfterTransferStarted: Bool = false
    ) async throws -> BleDevice {
        logger.info("模拟器环境开始天气推送：targetID=\(snapshot.id, privacy: .public), name=\(snapshot.name, privacy: .public)")
        transferPresentationMode = .backgroundShortcut
        beginBackgroundShortcutTransferRecord(for: snapshot)
        guard !snapshot.id.trimmed.isEmpty else {
            logger.error("模拟器环境天气推送失败：目标设备信息不完整。")
            updateBackgroundShortcutTransferRecord(phase: .failed, errorMessage: BleTransferError.deviceNotReady.localizedDescription, finish: true)
            throw BleTransferError.deviceNotReady
        }

        guard !isTransferInProgress, automatedPushContinuation == nil else {
            logger.error("模拟器环境天气推送失败：当前已有传输任务。")
            updateBackgroundShortcutTransferRecord(phase: .failed, errorMessage: BleTransferError.transferBusy.localizedDescription, finish: true)
            throw BleTransferError.transferBusy
        }

        guard let device = devices.first(where: { $0.id == snapshot.id }) ?? selectedDevice ?? devices.first else {
            logger.error("模拟器环境天气推送失败：没有找到可用设备。")
            updateBackgroundShortcutTransferRecord(phase: .failed, errorMessage: BleTransferError.deviceNotFound(snapshot.name).localizedDescription, finish: true)
            throw BleTransferError.deviceNotFound(snapshot.name)
        }

        automatedTargetDeviceID = snapshot.id
        automatedMatchedDevice = device
        automatedPushImage = image
        automatedPushDisplayImage = displayImage ?? image
        automatedReturnPolicy = returnAfterTransferStarted ? .returnAfterTransferStarted : .waitForCompletion

        return try await withCheckedThrowingContinuation { continuation in
            automatedPushContinuation = continuation
            // 后台快捷指令在开始扫描/连接前就申请执行时间，避免尚未传输就被挂起。
            beginTransferBackgroundTask()
            updateBackgroundShortcutTransferRecord(phase: .transferring, lastEvent: "模拟器：开始传输")
            transfer(image: image, to: device, algorithm: algorithm)
            resolveShortcutIntentAfterTransferStartedIfNeeded(device: device, reason: "模拟器：设备开始接收")
        }
    }

    func markLastTransferredImage(_ image: UIImage) {
        lastTransferredImage = image
        guard let device = connectedDevice ?? selectedDevice else { return }
        transferredImageStore.save(image, for: device.id)
    }

    func markLastTransferredImage(_ image: UIImage, for deviceID: String) {
        lastTransferredImage = image
        transferredImageStore.save(image, for: deviceID)
    }

    private func presentPromptIfNeeded(for device: BleDevice?) {
        guard let device else { return }
        guard connectedDevice?.id != device.id else { return }
        guard !rememberedDeviceIDs.contains(device.id) else { return }
        guard proximityPromptDevice?.id != device.id else { return }

        proximityPromptDevice = device
        connectionPhase = .idle
        appendDiagnosticLog("显示靠近连接弹窗：\(device.name)")
    }

    private func rememberDevice(_ device: BleDevice) {
        rememberedDeviceIDs.insert(device.id)
        persistRememberedDeviceIDs()
    }

    private func persistRememberedDeviceIDs() {
        UserDefaults.standard.set(Array(rememberedDeviceIDs), forKey: Self.rememberedDeviceIDsKey)
    }

    private func syncLastTransferredImage(for device: BleDevice) {
        if let image = transferredImageStore.loadImage(for: device.id) {
            lastTransferredImage = image
        }
    }

    private func appendDiagnosticLog(_ message: String, level: DeviceDiagnosticLogLevel = .info) {
        diagnosticLogs.append(DeviceDiagnosticLogEntry(timestamp: Date(), level: level, message: message))
        if diagnosticLogs.count > BleDiagnosticsStorage.maxLogCount {
            diagnosticLogs.removeFirst(diagnosticLogs.count - BleDiagnosticsStorage.maxLogCount)
        }
    }

    private func finishAutomatedPush(with result: Result<BleDevice, Error>) {
        let continuation = automatedPushContinuation
        let displayImage = automatedPushDisplayImage
        automatedPushContinuation = nil
        automatedTargetDeviceID = nil
        automatedMatchedDevice = nil
        automatedPushImage = nil
        automatedPushDisplayImage = nil
        automatedReturnPolicy = .waitForCompletion
        activeTransferDisplayImage = nil
        activeTransferAlgorithm = nil
        // 模拟器也保持同样的收尾语义，避免预览调试时留下后台任务。
        endTransferBackgroundTask()
        transferPresentationMode = .interactive

        switch result {
        case .success(let device):
            transferProgress = 1
            transferPhase = .succeeded
            if let displayImage {
                markLastTransferredImage(displayImage, for: device.id)
            }
            endLiveTransferActivityIfNeeded(finalPhaseTitle: transferPhase.title)
            updateBackgroundShortcutTransferRecord(phase: .succeeded, finish: true)
            appendDiagnosticLog("自动推送完成：\(device.name)", level: .success)
            continuation?.resume(returning: device)
        case .failure(let error):
            transferPhase = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
            endLiveTransferActivityIfNeeded(finalPhaseTitle: transferPhase.title)
            updateBackgroundShortcutTransferRecord(phase: .failed, errorMessage: error.localizedDescription, finish: true)
            appendDiagnosticLog("自动推送失败：\(error.localizedDescription)", level: .error)
            continuation?.resume(throwing: error)
        }
    }

    private func resolveShortcutIntentAfterTransferStartedIfNeeded(device: BleDevice, reason: String) {
        guard transferPresentationMode == .backgroundShortcut else { return }
        guard automatedReturnPolicy == .returnAfterTransferStarted else { return }
        guard let continuation = automatedPushContinuation else { return }

        automatedPushContinuation = nil
        updateBackgroundShortcutTransferRecord(phase: .transferring, lastEvent: "已返回快捷指令：\(reason)")
        appendDiagnosticLog("快捷指令已返回，后台继续传输：\(reason)", level: .success)
        continuation.resume(returning: device)
    }

    private func beginTransferAuxiliaryWorkIfNeeded(for deviceName: String) {
        beginTransferBackgroundTask()
        startLiveTransferActivityIfNeeded(deviceName: deviceName)
    }

    private func endTransferAuxiliaryWorkIfNeeded(finalPhaseTitle: String) {
        endLiveTransferActivityIfNeeded(finalPhaseTitle: finalPhaseTitle)
        endTransferBackgroundTask()
    }

    private func startLiveTransferActivityIfNeeded(deviceName: String? = nil) {
        guard shouldShowLiveTransferActivity else { return }
        let name = deviceName ?? (selectedDevice?.name ?? connectedDevice?.name ?? "墨水屏")
        // 前台传输不创建实时活动；只有后台/快捷指令传输才接入灵动岛。
        liveTransferActivity.startOrUpdate(deviceName: name, progress: transferProgress, phaseTitle: transferPhase.title)
    }

    private func updateLiveTransferActivityIfNeeded() {
        guard shouldShowLiveTransferActivity else { return }
        guard liveTransferActivity.isActive else { return }
        liveTransferActivity.update(progress: transferProgress, phaseTitle: transferPhase.title)
    }

    private func endLiveTransferActivityIfNeeded(finalPhaseTitle: String) {
        guard liveTransferActivity.isActive else { return }
        liveTransferActivity.end(progress: transferProgress, phaseTitle: finalPhaseTitle, immediate: true)
    }

    private var shouldShowLiveTransferActivity: Bool {
        transferPresentationMode == .backgroundShortcut || !isAppInForeground
    }

    private var isTransferInProgress: Bool {
        transferPhase == .preparing || transferPhase == .transferring
    }

    private func beginTransferBackgroundTask() {
        endTransferBackgroundTask()

        transferBackgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "BleImageTransfer") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.endTransferBackgroundTask()
                if self.transferPresentationMode == .backgroundShortcut {
                    self.finishAutomatedPush(with: .failure(BleTransferError.backgroundTimeExpired))
                }
            }
        }
    }

    private func endTransferBackgroundTask() {
        guard transferBackgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(transferBackgroundTaskID)
        transferBackgroundTaskID = .invalid
    }
}
#else
@MainActor
final class BleTransferService: NSObject, ObservableObject, PickBleManagerDelegate {
    private static let rememberedDeviceIDsKey = "rememberedProximityDeviceIDs"
    static let shared = BleTransferService()
    private let logger = Logger(subsystem: "com.xiaogousi.online.potato-card", category: "WeatherShortcut")

    @Published private(set) var bluetoothState: BlePowerState = .unknown
    @Published private(set) var devices: [BleDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var connectionPhase: BleConnectionPhase = .idle
    @Published private(set) var connectedDevice: BleDevice?
    @Published private(set) var proximityPromptDevice: BleDevice?
    @Published private(set) var rememberedDeviceIDs: Set<String>
    @Published private(set) var transferPhase: TransferPhase = .idle
    @Published private(set) var transferProgress: Double = 0
    @Published private(set) var currentBlock: Int = 0
    @Published private(set) var currentAddress = ""
    @Published private(set) var errorMessage: String?
    @Published var selectedDevice: BleDevice?
    @Published private(set) var lastTransferredImage: UIImage?
    @Published private(set) var ditherAlgorithm: EInkDitherAlgorithm = .floydSteinberg
    @Published private(set) var activeTransferAlgorithm: EInkDitherAlgorithm?
    @Published private(set) var diagnosticLogs: [DeviceDiagnosticLogEntry] = []
    @Published private(set) var lastBackgroundShortcutTransfer: BackgroundShortcutTransferRecord?
    @Published private(set) var displayedBatteryPercent: Int?
    @Published private(set) var batteryDisplayState: BatteryDisplayState = .empty
    // “正在同步”的发起方标识符（与模拟器版同义）。
    @Published private(set) var currentSyncSource: String?
    private var wantsForegroundAutoScan = false
    private var lastBatteryByDeviceID: [String: DeviceBatterySnapshot]
    private var batteryRefreshTimeoutTask: Task<Void, Never>?
    private var batteryRefreshGeneration = 0

    private lazy var manager = PickBleManager.shared()
    private let transferredImageStore = TransferredDeviceImageStore()
    private let liveTransferActivity = LiveTransferActivityController()
    private var transferBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var didStartManagerWork = false
    private var transferPresentationMode: BleTransferPresentationMode = .interactive
    private var isAppInForeground = true
    private var automatedPushContinuation: CheckedContinuation<BleDevice, Error>?
    private var automatedPushImage: UIImage?
    private var automatedPushDisplayImage: UIImage?
    private var automatedPushAlgorithm: EInkDitherAlgorithm?
    private var automatedReturnPolicy: BackgroundShortcutReturnPolicy = .waitForCompletion
    private var activeTransferDisplayImage: UIImage?
    private var automatedTargetSnapshot: WeatherTargetDeviceSnapshot?
    private var automatedMatchedDevice: BleDevice?
    private var automatedScanTimeoutTask: Task<Void, Never>?
    private var automatedTransferTimeoutTask: Task<Void, Never>?
    private var transferBackgroundTask: BleBackgroundTaskBox?
    private var lastLoggedTransferPercentBucket = -1

    override init() {
        ShortcutDebugLog.log("BleTransferService", "init begin pid=\(ProcessInfo.processInfo.processIdentifier)")
        rememberedDeviceIDs = Set(UserDefaults.standard.stringArray(forKey: Self.rememberedDeviceIDsKey) ?? [])
        lastBatteryByDeviceID = DeviceBatteryCacheStore.load()
        if let savedAlgorithm = UserDefaults.standard.string(forKey: BleDiagnosticsStorage.ditherAlgorithmKey),
           let algorithm = EInkDitherAlgorithm(rawValue: savedAlgorithm) {
            ditherAlgorithm = algorithm
        }
        lastBackgroundShortcutTransfer = Self.loadBackgroundShortcutTransferRecord()
        lastTransferredImage = transferredImageStore.loadLatestImage()
        super.init()
        appendDiagnosticLog("调试会话已启动，算法：\(ditherAlgorithm.title)")
        restoreDisplayedBatteryFromCache()
        ShortcutDebugLog.log("BleTransferService", "init end")
    }

    convenience init(forcePreviewPrompt: Bool) {
        self.init()
    }

    func beginForegroundAutoScan() {
        ensureManagerStarted()
        guard !isTransferInProgress else { return }
        wantsForegroundAutoScan = true
        appendDiagnosticLog("请求前台自动扫描")
        guard bluetoothState.canScan else { return }
        startScan()
    }

    func startScan() {
        ensureManagerStarted()
        guard !isTransferInProgress else { return }
        guard bluetoothState.canScan else {
            logger.notice("蓝牙未就绪，跳过本次扫描请求：\(self.bluetoothState.title, privacy: .public)")
            appendDiagnosticLog("蓝牙未就绪，跳过扫描：\(bluetoothState.title)", level: .warning)
            return
        }
        errorMessage = nil
        devices.removeAll()
        selectedDevice = connectedDevice
        isScanning = true
        appendDiagnosticLog("开始扫描附近设备")
        beginBatteryRefreshWindow()
        manager.stopScan()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.manager.startScan()
        }
    }

    func stopScan() {
        wantsForegroundAutoScan = false
        isScanning = false
        appendDiagnosticLog("停止扫描")
        guard bluetoothState.canScan else { return }
        manager.stopScan()
    }

    func handleSceneBecameActive() {
        ShortcutDebugLog.log("BleTransferService", "handleSceneBecameActive enter inProgress=\(isTransferInProgress) hasAuto=\(hasAutomatedPush) bt=\(bluetoothState.title)")
        isAppInForeground = true
        endLiveTransferActivityIfNeeded(finalPhaseTitle: transferPhase.title)
        guard !isTransferInProgress else {
            ShortcutDebugLog.log("BleTransferService", "handleSceneBecameActive skip: transfer in progress")
            return
        }
        beginForegroundAutoScan()
        ShortcutDebugLog.log("BleTransferService", "handleSceneBecameActive done")
    }

    func handleSceneEnteredBackground() {
        ShortcutDebugLog.log("BleTransferService", "handleSceneEnteredBackground inProgress=\(isTransferInProgress)")
        isAppInForeground = false
        wantsForegroundAutoScan = false
        guard !isTransferInProgress else {
            startLiveTransferActivityIfNeeded()
            return
        }
        stopScan()
    }

    func select(_ device: BleDevice) {
        selectedDevice = device
        appendDiagnosticLog("选择设备：\(device.name)")
        restoreDisplayedBatteryFromCache(for: device)
        updateBatteryDisplay(from: device, source: .live)
        syncLastTransferredImage(for: device)
    }

    func connect(_ device: BleDevice) {
        stopScan()
        selectedDevice = device
        connectionPhase = .connecting
        restoreDisplayedBatteryFromCache(for: device)
        appendDiagnosticLog("开始连接设备：\(device.name)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.connectedDevice = device
            self.selectedDevice = device
            self.connectionPhase = .connected
            self.rememberDevice(device)
            self.updateBatteryDisplay(from: device, source: .live)
            self.syncLastTransferredImage(for: device)
            self.appendDiagnosticLog("设备已连接：\(device.name)", level: .success)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self else { return }
                if self.proximityPromptDevice?.id == device.id {
                    self.proximityPromptDevice = nil
                }
            }
        }
    }

    func dismissProximityPrompt() {
        postponeProximityPrompt()
    }

    func postponeProximityPrompt() {
        proximityPromptDevice = nil
        appendDiagnosticLog("稍后连接当前设备")
        if connectionPhase != .connected {
            connectionPhase = .idle
        }
    }

    // 同步发起方标识符（与模拟器版同义）。
    func beginSync(source: String) {
        currentSyncSource = source
    }

    func endSync(source: String) {
        if currentSyncSource == source {
            currentSyncSource = nil
        }
    }

    func transfer(image: UIImage, displayImage: UIImage? = nil, to device: BleDevice, algorithm: EInkDitherAlgorithm? = nil) {
        resetAutomatedPushStateForInteractiveTransfer()
        performTransfer(image: image, displayImage: displayImage, to: device, presentationMode: .interactive, algorithm: algorithm)
    }

    private func performTransfer(
        image: UIImage,
        displayImage: UIImage? = nil,
        to device: BleDevice,
        presentationMode: BleTransferPresentationMode,
        algorithm: EInkDitherAlgorithm? = nil
    ) {
        ensureManagerStarted()
        let transferAlgorithm = algorithm ?? ditherAlgorithm
        guard !isTransferInProgress else {
            errorMessage = BleTransferError.transferBusy.localizedDescription
            appendDiagnosticLog("传输被拒绝：当前已有任务", level: .warning)
            return
        }

        guard bluetoothState.canScan else {
            let message = BleTransferError.bluetoothUnavailable(bluetoothState.title).localizedDescription
            transferPhase = .failed(message)
            errorMessage = message
            appendDiagnosticLog("传输失败：\(message)", level: .error)
            return
        }

        // 优先使用扫描列表里的新设备对象，避免长时间停留后把过期 rawDevice 传给 SDK。
        let transferDevice = freshestDevice(for: device)
        guard let preflight = validateTransferInputs(
            image: image,
            device: transferDevice,
            requestedDevice: device,
            presentationMode: presentationMode,
            algorithm: transferAlgorithm
        ) else { return }

        transferPresentationMode = presentationMode
        selectedDevice = transferDevice
        transferPhase = .preparing
        transferProgress = 0
        currentBlock = 0
        currentAddress = transferDevice.address
        errorMessage = nil
        lastLoggedTransferPercentBucket = -1
        activeTransferAlgorithm = transferAlgorithm
        activeTransferDisplayImage = displayImage
        appendDiagnosticLog("开始传输：\(transferDevice.name)，算法：\(transferAlgorithm.title)")
        beginTransferAuxiliaryWorkIfNeeded(for: transferDevice.name)

        logger.info("即将调用 PickBleManager.updateImageWithDevice:image: deviceID=\(transferDevice.id, privacy: .public), imageDataSize=\(preflight.imageDataSize, privacy: .public), serviceUUID=\(preflight.serviceUUID, privacy: .public), controlUUID=\(preflight.controlCharacteristicUUID, privacy: .public), writeUUID=\(preflight.writeCharacteristicUUID, privacy: .public)")
        appendDiagnosticLog("SDK 调用前：device=\(transferDevice.id)，imageData=\(preflight.imageDataSize) bytes")
        manager.updateImage(withDevice: transferDevice.sdkTransferDevice, image: image)
    }

    private func validateTransferInputs(
        image: UIImage,
        device: BleDevice,
        requestedDevice: BleDevice,
        presentationMode: BleTransferPresentationMode,
        algorithm: EInkDitherAlgorithm
    ) -> BleTransferPreflight? {
        let selectedSummary = selectedDevice?.debugSummary ?? "nil"
        let connectedSummary = connectedDevice?.debugSummary ?? "nil"
        let rawKeys = device.rawDevice.keys
            .map { String(describing: $0) }
            .sorted()
            .joined(separator: ",")
        let presentationModeText = transferPresentationModeText(presentationMode)
        let requestedDeviceSummary = requestedDevice.debugSummary

        logger.info("transfer start: presentationMode=\(presentationModeText, privacy: .public), algorithm=\(algorithm.title, privacy: .public), selectedDevice=\(selectedSummary, privacy: .public), connectedDevice=\(connectedSummary, privacy: .public), requestedDevice=\(requestedDeviceSummary, privacy: .public), transferDevice=\(device.debugSummary, privacy: .public), rawKeys=\(rawKeys, privacy: .public)")
        // 这些日志同步进首页设置弹窗，真机联调时不用只依赖 Xcode 控制台。
        appendDiagnosticLog("传输开始：mode=\(presentationModeText)，算法=\(algorithm.title)")
        appendDiagnosticLog("设备选择：selected=\(selectedDevice?.id ?? "nil")，connected=\(connectedDevice?.id ?? "nil")，target=\(device.id)")
        appendDiagnosticLog("设备 rawKeys：\(rawKeys.isEmpty ? "nil" : rawKeys)")

        guard presentationMode == .backgroundShortcut || selectedDevice != nil || connectedDevice != nil else {
            return failTransferPreflight(
                BleTransferError.deviceInfoInvalid,
                detail: "selectedDevice 和 connectedDevice 均为空",
                presentationMode: presentationMode
            )
        }

        guard image.size.width > 0, image.size.height > 0 else {
            return failTransferPreflight(
                BleTransferError.imageInvalid,
                detail: "UIImage size 异常：\(image.size.width)x\(image.size.height)",
                presentationMode: presentationMode
            )
        }

        guard let cgImage = image.cgImage else {
            return failTransferPreflight(
                BleTransferError.imageInvalid,
                detail: "UIImage.cgImage 为空",
                presentationMode: presentationMode
            )
        }

        guard let imageData = image.pngData(), !imageData.isEmpty else {
            return failTransferPreflight(
                BleTransferError.imageInvalid,
                detail: "UIImage.pngData 生成失败或为空",
                presentationMode: presentationMode
            )
        }

        guard !device.id.trimmed.isEmpty else {
            return failTransferPreflight(
                BleTransferError.deviceInfoInvalid,
                detail: "设备 id 为空",
                presentationMode: presentationMode
            )
        }

        let mac = firstNonEmptyRawString(["mac", "macAddress", "address"], in: device.rawDevice, fallback: device.address)
        guard let mac else {
            return failTransferPreflight(
                BleTransferError.deviceInfoInvalid,
                detail: "设备 mac/macAddress/address 均为空",
                presentationMode: presentationMode
            )
        }

        let name = firstNonEmptyRawString(["name", "localName"], in: device.rawDevice, fallback: device.name)
        guard let name else {
            return failTransferPreflight(
                BleTransferError.deviceInfoInvalid,
                detail: "设备 name/localName 为空",
                presentationMode: presentationMode
            )
        }

        // 协议文档固定使用 FEF0/FEF1/FEF2；SDK 扫描字典通常不带这些字段，缺失时用协议常量记录。
        let serviceUUID = firstNonEmptyRawString(["serviceUUID", "serviceUuid", "service"], in: device.rawDevice, fallback: "FEF0")
        let controlUUID = firstNonEmptyRawString(["controlCharacteristicUUID", "notifyCharacteristicUUID", "characteristicUUID"], in: device.rawDevice, fallback: "FEF1")
        let writeUUID = firstNonEmptyRawString(["writeCharacteristicUUID", "writeUUID"], in: device.rawDevice, fallback: "FEF2")

        guard let serviceUUID, let controlUUID, let writeUUID else {
            return failTransferPreflight(
                BleTransferError.deviceInfoInvalid,
                detail: "服务或特征 UUID 为空",
                presentationMode: presentationMode
            )
        }

        logger.info("transfer device info: id=\(device.id, privacy: .public), mac=\(mac, privacy: .public), name=\(name, privacy: .public), serviceUUID=\(serviceUUID, privacy: .public), controlCharacteristicUUID=\(controlUUID, privacy: .public), writeCharacteristicUUID=\(writeUUID, privacy: .public)")
        logger.info("transfer image info: imageSize=\(image.size.width, privacy: .public)x\(image.size.height, privacy: .public), scale=\(image.scale, privacy: .public), cgImageSize=\(cgImage.width, privacy: .public)x\(cgImage.height, privacy: .public), imageDataSize=\(imageData.count, privacy: .public)")
        appendDiagnosticLog("设备字段：id=\(device.id)，mac=\(mac)，name=\(name)")
        appendDiagnosticLog("协议字段：service=\(serviceUUID)，control=\(controlUUID)，write=\(writeUUID)")
        appendDiagnosticLog("图片字段：ui=\(Int(image.size.width))x\(Int(image.size.height))，cg=\(cgImage.width)x\(cgImage.height)，data=\(imageData.count) bytes")
        appendDiagnosticLog("传输预检通过：\(device.name) · \(Int(image.size.width))x\(Int(image.size.height)) · \(imageData.count) bytes")

        return BleTransferPreflight(
            imageDataSize: imageData.count,
            serviceUUID: serviceUUID,
            controlCharacteristicUUID: controlUUID,
            writeCharacteristicUUID: writeUUID
        )
    }

    private func failTransferPreflight(
        _ error: BleTransferError,
        detail: String,
        presentationMode: BleTransferPresentationMode
    ) -> BleTransferPreflight? {
        let message = error.localizedDescription
        transferPhase = .failed(message)
        errorMessage = message
        logger.error("传输预检失败：\(message, privacy: .public) detail=\(detail, privacy: .public)")
        appendDiagnosticLog("传输预检失败：\(message) · \(detail)", level: .error)

        if presentationMode == .backgroundShortcut {
            finishAutomatedPush(with: .failure(error))
        }

        return nil
    }

    private func firstNonEmptyRawString(_ keys: [String], in rawDevice: [AnyHashable: Any], fallback: String? = nil) -> String? {
        for key in keys {
            guard let value = rawDevice[key] else { continue }
            if let string = normalizedNonEmptyString(value) {
                return string
            }
        }

        return normalizedNonEmptyString(fallback)
    }

    private func normalizedNonEmptyString(_ value: Any?) -> String? {
        guard let value else { return nil }

        let string: String
        if let rawString = value as? String {
            string = rawString
        } else if let number = value as? NSNumber {
            string = number.stringValue
        } else {
            string = String(describing: value)
        }

        let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedString.isEmpty, trimmedString != "<null>" else { return nil }
        return trimmedString
    }

    private func transferPresentationModeText(_ mode: BleTransferPresentationMode) -> String {
        switch mode {
        case .interactive:
            return "interactive"
        case .backgroundShortcut:
            return "backgroundShortcut"
        }
    }

    func setDitherAlgorithm(_ algorithm: EInkDitherAlgorithm) {
        guard ditherAlgorithm != algorithm else { return }
        ditherAlgorithm = algorithm
        UserDefaults.standard.set(algorithm.rawValue, forKey: BleDiagnosticsStorage.ditherAlgorithmKey)
        appendDiagnosticLog("切换图像算法：\(algorithm.title)")
    }

    func clearDiagnosticLogs() {
        diagnosticLogs.removeAll()
    }

    func pushWeatherImage(
        _ image: UIImage,
        displayImage: UIImage? = nil,
        toTargetDeviceSnapshot snapshot: WeatherTargetDeviceSnapshot,
        algorithm: EInkDitherAlgorithm? = nil,
        returnAfterTransferStarted: Bool = false
    ) async throws -> BleDevice {
        ensureManagerStarted()
        logger.info("开始蓝牙天气推送：targetID=\(snapshot.id, privacy: .public), name=\(snapshot.name, privacy: .public)")
        ShortcutDebugLog.log("BleTransferService", "pushWeatherImage enter targetID=\(snapshot.id) name=\(snapshot.name) returnAfter=\(returnAfterTransferStarted) bt=\(bluetoothState.title) connected=\(connectedDevice?.id ?? "nil")")
        transferPresentationMode = .backgroundShortcut
        beginBackgroundShortcutTransferRecord(for: snapshot)

        do {
            try await waitForBluetoothReadyIfNeeded()
        } catch {
            logger.error("蓝牙天气推送失败：蓝牙状态不可用，state=\(self.bluetoothState.title, privacy: .public)")
            transferPresentationMode = .interactive
            updateBackgroundShortcutTransferRecord(phase: .failed, errorMessage: error.localizedDescription, finish: true)
            throw error
        }

        guard !isTransferInProgress, automatedPushContinuation == nil else {
            logger.error("蓝牙天气推送失败：当前已有传输任务。")
            transferPresentationMode = .interactive
            updateBackgroundShortcutTransferRecord(phase: .failed, errorMessage: BleTransferError.transferBusy.localizedDescription, finish: true)
            throw BleTransferError.transferBusy
        }

        guard !snapshot.id.trimmed.isEmpty else {
            logger.error("蓝牙天气推送失败：目标设备信息不完整。")
            transferPresentationMode = .interactive
            updateBackgroundShortcutTransferRecord(phase: .failed, errorMessage: BleTransferError.deviceNotReady.localizedDescription, finish: true)
            throw BleTransferError.deviceNotReady
        }

        automatedPushImage = image
        automatedPushDisplayImage = displayImage ?? image
        automatedPushAlgorithm = algorithm
        automatedReturnPolicy = returnAfterTransferStarted ? .returnAfterTransferStarted : .waitForCompletion
        automatedTargetSnapshot = snapshot

        return try await withCheckedThrowingContinuation { continuation in
            automatedPushContinuation = continuation
            // 后台快捷指令在开始扫描/连接前就申请执行时间，避免尚未传输就被挂起。
            beginTransferBackgroundTask()

            if let device = self.connectedDevice, self.device(device, matches: snapshot) {
                self.logger.info("目标设备当前已连接，直接开始传输。")
                ShortcutDebugLog.log("BleTransferService", "already connected, start transfer to \(device.id)")
                self.startAutomatedTransfer(to: device)
                return
            }

            if let device = self.devices.first(where: { self.device($0, matches: snapshot) }) {
                self.logger.info("使用当前会话里缓存的目标设备，避免后台重新扫描失败。")
                ShortcutDebugLog.log("BleTransferService", "using cached scanned device \(device.id)")
                self.startAutomatedTransfer(to: device)
                return
            }

            // 没有可用缓存时再扫描，后台扫描可能被系统限制。
            self.logger.info("后台运行或未命中当前会话，开始自动扫描目标设备。")
            ShortcutDebugLog.log("BleTransferService", "no cached device, start automated scan")
            self.startAutomatedScan(for: snapshot)
        }
    }

    nonisolated func didBluetoothStatusNotification(_ state: Int) {
        Task { @MainActor in
            self.bluetoothState = BlePowerState(sdkState: state)
            self.appendDiagnosticLog("蓝牙状态：\(self.bluetoothState.title)")

            if !self.bluetoothState.canScan {
                self.isScanning = false
                if self.hasAutomatedPush, !self.isTransferInProgress {
                    self.finishAutomatedPush(with: .failure(BleTransferError.bluetoothUnavailable(self.bluetoothState.title)))
                }
            } else if self.wantsForegroundAutoScan && !self.isScanning && !self.isTransferInProgress {
                // 蓝牙状态晚于页面启动才 ready 时，即使已有连接设备，也补扫一次刷新实时电量。
                self.startScan()
            }
        }
    }

    nonisolated func bluetoothSearchDevice(_ device: [AnyHashable: Any]) {
        let payloadBox = BlePayloadBox(payload: device)

        Task { @MainActor in
            let bleDevice = BleDevice(rawDevice: payloadBox.payload)
            self.updateBatteryDisplay(from: bleDevice, source: .live)
            self.persistDeviceForBackgroundShortcut(bleDevice)

            if let index = self.devices.firstIndex(where: { $0.id == bleDevice.id }) {
                self.devices[index] = bleDevice
                if self.selectedDevice?.id == bleDevice.id {
                    self.selectedDevice = bleDevice
                }
                if self.connectedDevice?.id == bleDevice.id {
                    self.connectedDevice = bleDevice
                }
                if self.automatedTargetSnapshot != nil {
                    self.logger.info("自动扫描发现设备：\(bleDevice.debugSummary, privacy: .public)")
                }
                if let snapshot = self.automatedTargetSnapshot, self.device(bleDevice, matches: snapshot) {
                    self.startAutomatedTransfer(to: bleDevice)
                }
                return
            }

            self.devices.append(bleDevice)
            self.appendDiagnosticLog("发现设备：\(bleDevice.name) · \(bleDevice.profile.displaySize)")
            if self.selectedDevice == nil {
                self.selectedDevice = bleDevice
            }
            if self.automatedTargetSnapshot != nil {
                self.logger.info("自动扫描发现设备：\(bleDevice.debugSummary, privacy: .public)")
            }
            if let snapshot = self.automatedTargetSnapshot, self.device(bleDevice, matches: snapshot) {
                self.startAutomatedTransfer(to: bleDevice)
                return
            }
            self.presentPromptIfNeeded(for: bleDevice)
        }
    }

    nonisolated func updateProgress(_ device: [AnyHashable: Any]) {
        let payloadBox = BlePayloadBox(payload: device)

        Task { @MainActor in
            let device = payloadBox.payload
            let type = (device["type"] as? NSNumber)?.intValue ?? device["type"] as? Int ?? -1
            // 进度回调优先使用设备编号，避免名称变化导致设备标识漂移。
            let address = (device["mac"] as? String)
                ?? (device["macAddress"] as? String)
                ?? (device["address"] as? String)
                ?? self.currentAddress

            if type == 0 {
                guard self.isTransferInProgress else { return }

                let percent = (device["percent"] as? NSNumber)?.doubleValue ?? device["percent"] as? Double ?? 0
                let block = (device["currentBlock"] as? NSNumber)?.intValue ?? device["currentBlock"] as? Int ?? 0
                let normalizedPercent = percent > 1 ? percent / 100 : percent
                self.logger.info("收到蓝牙传输进度：percent=\(normalizedPercent, privacy: .public), block=\(block, privacy: .public)")

                self.currentAddress = address
                self.currentBlock = block
                // SDK 偶尔会在开始回调后再给一次 0%，UI 进度只前进不回退。
                let nextProgress = min(max(normalizedPercent, 0), 1)
                self.transferProgress = max(self.transferProgress, nextProgress)
                self.transferPhase = .transferring
                let percentBucket = Int((self.transferProgress * 100).rounded(.down)) / 5
                if percentBucket != self.lastLoggedTransferPercentBucket {
                    self.lastLoggedTransferPercentBucket = percentBucket
                    self.appendDiagnosticLog("传输进度：\(Int(self.transferProgress * 100))% · block \(block)")
                }
                if self.transferProgress > 0 || block > 0 {
                    self.resolveShortcutIntentAfterTransferStartedIfNeeded(
                        device: self.automatedMatchedDevice ?? self.selectedDevice ?? BleDevice(rawDevice: device),
                        reason: "收到协议进度/块请求，block \(block)"
                    )
                }
                self.updateLiveTransferActivityIfNeeded()
                return
            }

            guard type == 1 else { return }

            let status = (device["status"] as? NSNumber)?.intValue ?? device["status"] as? Int ?? -1
            self.currentAddress = address
            self.logger.info("收到蓝牙传输状态：status=\(status, privacy: .public), address=\(address, privacy: .public)")

            switch status {
            case 3:
                guard self.isTransferInProgress else { return }

                self.transferPhase = .failed("传输出错")
                self.errorMessage = "设备 \(address.isEmpty ? "未知" : address) 传输出错，请重试。"
                self.appendDiagnosticLog("传输失败：\(self.errorMessage ?? "设备传输出错")", level: .error)
                self.endTransferAuxiliaryWorkIfNeeded(finalPhaseTitle: "传输失败")
                self.finishAutomatedPush(with: .failure(BleTransferError.transferFailed(self.errorMessage ?? "设备传输出错，请重试。")))
            case 4:
                guard self.isTransferInProgress else { return }

                // 只切换到传输中，不再人为显示 1%，避免随后真实 0% 回调造成视觉回跳。
                self.transferPhase = .transferring
                self.appendDiagnosticLog("设备开始接收图片")
                self.updateBackgroundShortcutTransferRecord(
                    phase: .transferring,
                    lastEvent: "SDK status=4：设备开始接收，等待 0x05 ACK/进度"
                )
                self.updateLiveTransferActivityIfNeeded()
            case 5:
                guard self.isTransferInProgress else { return }

                self.transferProgress = 1
                self.transferPhase = .succeeded
                if let displayImage = self.activeTransferDisplayImage,
                   let deviceID = (self.automatedMatchedDevice ?? self.selectedDevice ?? self.connectedDevice)?.id {
                    self.markLastTransferredImage(displayImage, for: deviceID)
                }
                self.activeTransferDisplayImage = nil
                self.appendDiagnosticLog("传输成功", level: .success)
                self.endTransferAuxiliaryWorkIfNeeded(finalPhaseTitle: self.transferPhase.title)
                self.finishAutomatedPush(with: .success(self.automatedMatchedDevice ?? self.selectedDevice ?? BleDevice(rawDevice: device)))
            default:
                break
            }
        }
    }

    func markLastTransferredImage(_ image: UIImage) {
        lastTransferredImage = image
        guard let device = connectedDevice ?? selectedDevice else { return }
        transferredImageStore.save(image, for: device.id)
    }

    func markLastTransferredImage(_ image: UIImage, for deviceID: String) {
        lastTransferredImage = image
        transferredImageStore.save(image, for: deviceID)
    }

    private func presentPromptIfNeeded(for device: BleDevice) {
        guard automatedPushContinuation == nil else { return }
        guard connectedDevice?.id != device.id else { return }
        guard !rememberedDeviceIDs.contains(device.id) else { return }
        guard proximityPromptDevice?.id != device.id else { return }

        proximityPromptDevice = device
        connectionPhase = .idle
        appendDiagnosticLog("显示靠近连接弹窗：\(device.name)")
    }

    private func rememberDevice(_ device: BleDevice) {
        rememberedDeviceIDs.insert(device.id)
        persistRememberedDeviceIDs()
    }

    private func persistRememberedDeviceIDs() {
        UserDefaults.standard.set(Array(rememberedDeviceIDs), forKey: Self.rememberedDeviceIDsKey)
    }

    private func syncLastTransferredImage(for device: BleDevice) {
        if let image = transferredImageStore.loadImage(for: device.id) {
            lastTransferredImage = image
        }
    }

    private func appendDiagnosticLog(_ message: String, level: DeviceDiagnosticLogLevel = .info) {
        diagnosticLogs.append(DeviceDiagnosticLogEntry(timestamp: Date(), level: level, message: message))
        if diagnosticLogs.count > BleDiagnosticsStorage.maxLogCount {
            diagnosticLogs.removeFirst(diagnosticLogs.count - BleDiagnosticsStorage.maxLogCount)
        }
    }

    private func persistDeviceForBackgroundShortcut(_ device: BleDevice) {
        // 保存完整 rawDevice 给 CompatProbe 路径（后台路径需要补齐 SDK 内部依赖的 type/version/power 等字段）。
        CachedSDKDeviceDictStore.save(deviceID: device.id, rawDevice: device.rawDevice)
    }

    private func startCompatProbeIfEnabled(for snapshot: WeatherTargetDeviceSnapshot) {
        guard CardPushPreferences.compatibilityProbeEnabled else { return }
        // 没有缓存的 SDK rawDevice 字典时，probe 即使扫到也无法构造 SDK 期望的设备入参；跳过避免误导。
        guard CachedSDKDeviceDictStore.load(deviceID: snapshot.id) != nil else {
            ShortcutDebugLog.log("BleTransferService", "compat probe skip: no cached SDK device dict for \(snapshot.id); 请先打开 App 让前台扫描刷新一次")
            return
        }
        // 使用全局单例，以便 iOS 的 state restoration 能够在同一个 CBCentralManager 上回调。
        // probe didDiscover 后把设备喂回 BleTransferService，绕过 SDK 内部失效的后台扫描。
        BackgroundCompatProbe.shared.onDeviceDiscovered = { [weak self] peripheral, advertisementData, rssi in
            guard let self else { return }
            self.handleCompatProbeDiscovery(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi, expectedDeviceID: snapshot.id)
        }
        BackgroundCompatProbe.shared.start()
        ShortcutDebugLog.log("BleTransferService", "compat probe started for \(snapshot.id)")
    }

    private func stopCompatProbeIfRunning() {
        BackgroundCompatProbe.shared.onDeviceDiscovered = nil
        guard BackgroundCompatProbe.shared.isRunning else { return }
        BackgroundCompatProbe.shared.stop()
        ShortcutDebugLog.log("BleTransferService", "compat probe stopped")
    }

    // 把 CompatProbe 扫到的 peripheral 转成 PickBleManager 的设备字典格式，
    // 直接走和 bluetoothSearchDevice 一样的处理路径。
    private func handleCompatProbeDiscovery(
        peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber,
        expectedDeviceID: String
    ) {
        guard hasAutomatedPush, automatedMatchedDevice == nil else { return }

        // 设备名优先用广播里的 localName（一般包含 NEMR 编号），其次用 peripheral.name（PICKSMART 占位符）。
        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)?.trimmed
        let peripheralName = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (advertisedName?.isEmpty == false ? advertisedName : nil) ?? peripheralName ?? ""

        // 以前台扫到同设备时缓存的完整字典为基础，上面叠加本次广告的 rssi/name/peripheral。
        // 这样 type/version/power 等 SDK 内部必需字段就不会为 nil。
        var rawDevice: [AnyHashable: Any] = CachedSDKDeviceDictStore.load(deviceID: expectedDeviceID) ?? [:]
        rawDevice["device"] = peripheral
        rawDevice["rssi"] = rssi.intValue
        if !resolvedName.isEmpty {
            rawDevice["name"] = resolvedName
        } else if rawDevice["name"] == nil {
            rawDevice["name"] = expectedDeviceID
        }
        if rawDevice["mac"] == nil { rawDevice["mac"] = expectedDeviceID }
        if rawDevice["macAddress"] == nil { rawDevice["macAddress"] = expectedDeviceID }
        if rawDevice["address"] == nil { rawDevice["address"] = expectedDeviceID }
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            rawDevice["manufacturerData"] = manufacturerData
        }
        ShortcutDebugLog.log("BleTransferService", "compat probe rawDevice keys=\(rawDevice.keys.compactMap { $0 as? String }.sorted())")

        let bleDevice = BleDevice(rawDevice: rawDevice)
        ShortcutDebugLog.log("BleTransferService", "compat probe synthesized device id=\(bleDevice.id) name=\(bleDevice.name) for SDK")

        guard let snapshot = automatedTargetSnapshot, device(bleDevice, matches: snapshot) else {
            ShortcutDebugLog.log("BleTransferService", "compat probe device does not match target snapshot \(automatedTargetSnapshot?.id ?? "nil")")
            return
        }

        // 把发现到的设备塞进我们的本地列表，然后启动自动传输。
        if devices.first(where: { $0.id == bleDevice.id }) == nil {
            devices.append(bleDevice)
        }
        startAutomatedTransfer(to: bleDevice)
    }

    private func startAutomatedScan(for snapshot: WeatherTargetDeviceSnapshot) {
        logger.info("开始自动扫描设备：\(snapshot.name, privacy: .public)")
        appendDiagnosticLog("开始自动扫描：\(snapshot.name)")
        updateBackgroundShortcutTransferRecord(phase: .scanning, lastEvent: "开始扫描目标设备")
        ShortcutDebugLog.log("BleTransferService", "startAutomatedScan target=\(snapshot.id) bt=\(bluetoothState.title)")
        errorMessage = nil
        automatedMatchedDevice = nil
        devices.removeAll()
        selectedDevice = nil
        isScanning = true
        if bluetoothState.canScan {
            manager.stopScan()
        }

        startCompatProbeIfEnabled(for: snapshot)

        automatedScanTimeoutTask?.cancel()
        automatedScanTimeoutTask = Task { @MainActor [weak self] in
            // 后台扫描被下动设备广播间隔制约，金那奇（极低功耗）设备可能 10–20s 才会广播一次。
            // 在 30s UIApplication 后台预算内拉長到 24s，并在 8s/16s 中途重启扫描会话，最大化命中机会。
            for kickIndex in 0..<2 {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard let strongSelf = self, strongSelf.hasAutomatedPush, strongSelf.automatedMatchedDevice == nil else { return }
                guard strongSelf.bluetoothState.canScan else { continue }
                ShortcutDebugLog.log("BleTransferService", "scan kick #\(kickIndex + 1) (no match yet)")
                strongSelf.appendDiagnosticLog("后台扫描未命中，重新启动扫描 #\(kickIndex + 1)", level: .warning)
                strongSelf.manager.stopScan()
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let kickSelf = self, kickSelf.hasAutomatedPush, kickSelf.automatedMatchedDevice == nil else { return }
                guard kickSelf.bluetoothState.canScan else { continue }
                kickSelf.manager.startScan()
            }

            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, self.hasAutomatedPush, self.automatedMatchedDevice == nil else { return }
            if self.bluetoothState.canScan {
                self.manager.stopScan()
            }
            self.isScanning = false
            self.logger.error("自动扫描超时：\(snapshot.name, privacy: .public)")
            ShortcutDebugLog.log("BleTransferService", "automated scan timed out (24s) for \(snapshot.id)")
            self.finishAutomatedPush(with: .failure(BleTransferError.deviceNotFound(snapshot.name)))
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.hasAutomatedPush, self.bluetoothState.canScan else { return }
            self.manager.startScan()
        }
    }

    private func startAutomatedTransfer(to device: BleDevice) {
        guard hasAutomatedPush else { return }
        guard automatedMatchedDevice == nil, !isTransferInProgress else { return }
        guard let image = automatedPushImage else {
            logger.error("自动传输失败：待发送图片缺失。")
            finishAutomatedPush(with: .failure(BleTransferError.deviceNotReady))
            return
        }

        logger.info("开始自动传输到设备：\(device.name, privacy: .public)")
        updateBackgroundShortcutTransferRecord(phase: .transferring, lastEvent: "命中设备，调用 SDK 进入 0x01/0x02/0x03 准备阶段")
        automatedScanTimeoutTask?.cancel()
        automatedScanTimeoutTask = nil
        automatedMatchedDevice = device
        isScanning = false
        if bluetoothState.canScan {
            manager.stopScan()
        }
        performTransfer(image: image, displayImage: automatedPushDisplayImage, to: device, presentationMode: .backgroundShortcut, algorithm: automatedPushAlgorithm)

        automatedTransferTimeoutTask?.cancel()
        automatedTransferTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            guard let self, self.hasAutomatedPush else { return }
            self.endTransferBackgroundTask()
            self.logger.error("自动传输超时：\(device.name, privacy: .public)")
            self.finishAutomatedPush(with: .failure(BleTransferError.transferTimedOut))
        }
    }

    private func finishAutomatedPush(with result: Result<BleDevice, Error>) {
        let continuation = automatedPushContinuation
        let displayImage = automatedPushDisplayImage
        let hadContinuation = continuation != nil
        ShortcutDebugLog.log("BleTransferService", "finishAutomatedPush hadContinuation=\(hadContinuation) result=\(String(describing: result))")
        automatedPushContinuation = nil
        automatedPushImage = nil
        automatedPushDisplayImage = nil
        automatedPushAlgorithm = nil
        automatedReturnPolicy = .waitForCompletion
        automatedTargetSnapshot = nil
        automatedMatchedDevice = nil
        activeTransferDisplayImage = nil
        activeTransferAlgorithm = nil
        automatedScanTimeoutTask?.cancel()
        automatedScanTimeoutTask = nil
        automatedTransferTimeoutTask?.cancel()
        automatedTransferTimeoutTask = nil
        stopCompatProbeIfRunning()
        // 自动推送由快捷指令驱动，完成或失败时必须释放后台任务和 UI 状态。
        endTransferBackgroundTask()
        transferPresentationMode = .interactive

        switch result {
        case .success(let device):
            logger.info("自动推送完成：\(device.name, privacy: .public)")
            appendDiagnosticLog("自动推送完成：\(device.name)", level: .success)
            updateBackgroundShortcutTransferRecord(phase: .succeeded, finish: true)
            transferProgress = 1
            transferPhase = .succeeded
            if let displayImage {
                markLastTransferredImage(displayImage, for: device.id)
            }
            endLiveTransferActivityIfNeeded(finalPhaseTitle: transferPhase.title)
            continuation?.resume(returning: device)
        case .failure(let error):
            logger.error("自动推送失败：\(error.localizedDescription, privacy: .public)")
            appendDiagnosticLog("自动推送失败：\(error.localizedDescription)", level: .error)
            updateBackgroundShortcutTransferRecord(phase: .failed, errorMessage: error.localizedDescription, finish: true)
            transferPhase = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
            endLiveTransferActivityIfNeeded(finalPhaseTitle: transferPhase.title)
            continuation?.resume(throwing: error)
        }
    }

    private func resolveShortcutIntentAfterTransferStartedIfNeeded(device: BleDevice, reason: String) {
        guard transferPresentationMode == .backgroundShortcut else { return }
        guard automatedReturnPolicy == .returnAfterTransferStarted else { return }
        guard let continuation = automatedPushContinuation else { return }

        automatedPushContinuation = nil
        updateBackgroundShortcutTransferRecord(phase: .transferring, lastEvent: "已返回快捷指令：\(reason)")
        appendDiagnosticLog("快捷指令已返回，后台继续传输：\(reason)", level: .success)
        continuation.resume(returning: device)
    }

    private func resetAutomatedPushStateForInteractiveTransfer() {
        guard hasAutomatedPush || transferPresentationMode != .interactive else { return }

        automatedPushContinuation?.resume(throwing: BleTransferError.transferBusy)
        automatedPushContinuation = nil
        automatedPushImage = nil
        automatedPushDisplayImage = nil
        activeTransferDisplayImage = nil
        automatedTargetSnapshot = nil
        automatedMatchedDevice = nil
        automatedScanTimeoutTask?.cancel()
        automatedScanTimeoutTask = nil
        automatedTransferTimeoutTask?.cancel()
        automatedTransferTimeoutTask = nil
        endLiveTransferActivityIfNeeded(finalPhaseTitle: "传输取消")
        endTransferBackgroundTask()
        transferPresentationMode = .interactive
    }

    private func freshestDevice(for device: BleDevice) -> BleDevice {
        if let scannedDevice = devices.first(where: { $0.id == device.id }) {
            return scannedDevice
        }

        if let connectedDevice, connectedDevice.id == device.id {
            return connectedDevice
        }

        if let selectedDevice, selectedDevice.id == device.id {
            return selectedDevice
        }

        return device
    }

    private func device(_ device: BleDevice, matches snapshot: WeatherTargetDeviceSnapshot) -> Bool {
        let targets = Set([snapshot.id, snapshot.name, snapshot.address]
            .map { $0.trimmed }
            .filter { !$0.isEmpty })
        guard !targets.isEmpty else { return false }

        // 兼容供应商 SDK 在不同回调里使用 name / macAddress / address 的情况。
        let rawStringCandidates = ["name", "mac", "macAddress", "address", "localName"]
            .compactMap { device.rawDevice[$0] as? String }
        let candidates = Set(([device.id, device.name, device.address] + rawStringCandidates)
            .map { $0.trimmed }
            .filter { !$0.isEmpty })

        return !targets.isDisjoint(with: candidates)
    }

    private func ensureManagerStarted() {
        guard !didStartManagerWork else { return }
        didStartManagerWork = true
        // SDK 初始化可能触发系统蓝牙状态检查，延后到用户看到首屏后再启动。
        ShortcutDebugLog.log("BleTransferService", "ensureManagerStarted: setting delegate + startWork")
        manager.delegate = self
        manager.startWork()
        ShortcutDebugLog.log("BleTransferService", "ensureManagerStarted: startWork returned")
    }

    private func waitForBluetoothReadyIfNeeded() async throws {
        guard !bluetoothState.canScan else { return }

        switch bluetoothState {
        case .unknown, .reset:
            logger.info("蓝牙状态仍在初始化，等待系统 ready。")
        default:
            throw BleTransferError.bluetoothUnavailable(bluetoothState.title)
        }

        for _ in 0..<12 {
            try await Task.sleep(nanoseconds: 500_000_000)
            if bluetoothState.canScan { return }
            if bluetoothState != .unknown, bluetoothState != .reset {
                throw BleTransferError.bluetoothUnavailable(bluetoothState.title)
            }
        }

        throw BleTransferError.bluetoothReadyTimedOut
    }

    private func beginTransferAuxiliaryWorkIfNeeded(for deviceName: String) {
        beginTransferBackgroundTask()
        startLiveTransferActivityIfNeeded(deviceName: deviceName)
    }

    private func endTransferAuxiliaryWorkIfNeeded(finalPhaseTitle: String) {
        endLiveTransferActivityIfNeeded(finalPhaseTitle: finalPhaseTitle)
        endTransferBackgroundTask()
    }

    private func startLiveTransferActivityIfNeeded(deviceName: String? = nil) {
        guard shouldShowLiveTransferActivity else { return }
        let name = deviceName ?? (selectedDevice?.name ?? connectedDevice?.name ?? "墨水屏")
        // 前台传输不创建实时活动；只有后台/快捷指令传输才接入灵动岛。
        liveTransferActivity.startOrUpdate(deviceName: name, progress: transferProgress, phaseTitle: transferPhase.title)
    }

    private func updateLiveTransferActivityIfNeeded() {
        guard shouldShowLiveTransferActivity else { return }
        guard liveTransferActivity.isActive else { return }
        liveTransferActivity.update(progress: transferProgress, phaseTitle: transferPhase.title)
    }

    private func endLiveTransferActivityIfNeeded(finalPhaseTitle: String) {
        guard liveTransferActivity.isActive else { return }
        liveTransferActivity.end(progress: transferProgress, phaseTitle: finalPhaseTitle, immediate: true)
    }

    private var shouldShowLiveTransferActivity: Bool {
        transferPresentationMode == .backgroundShortcut || !isAppInForeground
    }

    private var isTransferInProgress: Bool {
        transferPhase == .preparing || transferPhase == .transferring
    }

    private var hasAutomatedPush: Bool {
        automatedPushContinuation != nil || automatedPushImage != nil
    }

    private func beginTransferBackgroundTask() {
        endTransferBackgroundTask()

        let taskBox = BleBackgroundTaskBox()
        transferBackgroundTask = taskBox
        transferBackgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "BleImageTransfer") { [weak self, taskBox] in
            // 过期回调里必须同步释放，否则系统会认为后台任务没有结束。
            taskBox.end()

            Task { @MainActor in
                guard let self else { return }
                self.logger.error("蓝牙传输后台执行时间到期。")
                if self.transferBackgroundTask === taskBox {
                    self.transferBackgroundTask = nil
                    self.transferBackgroundTaskID = .invalid
                }
                if self.transferPresentationMode == .backgroundShortcut, self.hasAutomatedPush {
                    self.handleBackgroundTaskExpired()
                }
            }
        }
        taskBox.set(transferBackgroundTaskID)
    }

    private func endTransferBackgroundTask() {
        transferBackgroundTask?.end()
        transferBackgroundTask = nil
        transferBackgroundTaskID = .invalid
    }

    private func handleBackgroundTaskExpired() {
        // 调试分支：后台时间到期先不立刻判失败，继续观察 CoreBluetooth/SDK 是否还会补回真实进度。
        if transferProgress <= 0, currentBlock <= 0 {
            logger.error("UIKit 后台执行时间到期，SDK 暂无真实进度，继续等待总超时。")
            appendDiagnosticLog("后台时间到期但继续等待 SDK 回调", level: .warning)
            updateBackgroundShortcutTransferRecord(
                phase: .transferring,
                lastEvent: "UIKit 后台时间到期，继续等待 SDK/协议进度"
            )
            return
        }

        if automatedMatchedDevice != nil || isTransferInProgress {
            logger.notice("UIKit 后台执行时间到期，已有传输进度，等待 SDK 最终回调或总超时。")
            return
        }

        // 如果还没发现目标设备，扫描阶段基本无法在后台继续稳定推进，直接给出明确失败。
        finishAutomatedPush(with: .failure(BleTransferError.backgroundTimeExpired))
    }
}
#endif

private extension BleTransferService {
    func beginBatteryRefreshWindow() {
        restoreDisplayedBatteryFromCache(for: connectedDevice ?? selectedDevice)
        batteryRefreshGeneration += 1
        let generation = batteryRefreshGeneration

        batteryRefreshTimeoutTask?.cancel()
        batteryRefreshTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self, !Task.isCancelled, self.batteryRefreshGeneration == generation else { return }
            guard self.batteryDisplayState != .live else { return }

            self.displayedBatteryPercent = nil
            self.batteryDisplayState = .empty
            self.appendDiagnosticLog("本次扫描 6 秒内未获取到有效电量，首页显示空白电池图标", level: .warning)
        }
    }

    func restoreDisplayedBatteryFromCache(for device: BleDevice? = nil) {
        let preferredDeviceID = device?.id
            ?? connectedDevice?.id
            ?? selectedDevice?.id
            ?? DeviceBatteryCacheStore.lastDeviceID

        guard let preferredDeviceID,
              let snapshot = lastBatteryByDeviceID[preferredDeviceID] else {
            displayedBatteryPercent = nil
            batteryDisplayState = .empty
            return
        }

        displayedBatteryPercent = snapshot.percent
        batteryDisplayState = .cached
        appendDiagnosticLog("读取缓存电量：device=\(preferredDeviceID)，percent=\(snapshot.percent)%")
    }

    func updateBatteryDisplay(from device: BleDevice?, source: BatteryDisplayState) {
        guard let device, let percent = device.batteryPercent else { return }

        let clampedPercent = min(100, max(0, percent))
        let oldSnapshot = lastBatteryByDeviceID[device.id]
        let voltageChanged: Bool
        if let oldVoltage = oldSnapshot?.voltage, let newVoltage = device.batteryVoltage {
            voltageChanged = abs(oldVoltage - newVoltage) > 0.001
        } else {
            voltageChanged = oldSnapshot?.voltage != nil || device.batteryVoltage != nil
        }
        let activeDeviceID = connectedDevice?.id ?? selectedDevice?.id
        let shouldApplyToHome = activeDeviceID == nil || activeDeviceID == device.id
        let isFirstLiveRefreshAfterCache = source == .live && shouldApplyToHome && batteryDisplayState != .live
        let shouldLog = oldSnapshot?.percent != clampedPercent || voltageChanged || isFirstLiveRefreshAfterCache

        let snapshot = DeviceBatterySnapshot(
            deviceID: device.id,
            percent: clampedPercent,
            voltage: device.batteryVoltage,
            updatedAt: Date()
        )
        lastBatteryByDeviceID[device.id] = snapshot
        DeviceBatteryCacheStore.save(lastBatteryByDeviceID)
        DeviceBatteryCacheStore.lastDeviceID = device.id

        if shouldApplyToHome {
            displayedBatteryPercent = clampedPercent
            batteryDisplayState = source
            batteryRefreshGeneration += 1
        }

        if shouldLog {
            let voltageText = device.batteryVoltage.map { String(format: "%.2fV", $0) } ?? "nil"
            appendDiagnosticLog("实时电压：device=\(device.id)，name=\(device.name)，voltage=\(voltageText)，percent=\(clampedPercent)%")
        }
    }

    static func loadBackgroundShortcutTransferRecord() -> BackgroundShortcutTransferRecord? {
        guard let data = UserDefaults.standard.data(forKey: BleDiagnosticsStorage.backgroundShortcutTransferKey) else {
            return nil
        }
        return try? JSONDecoder().decode(BackgroundShortcutTransferRecord.self, from: data)
    }

    func beginBackgroundShortcutTransferRecord(for snapshot: WeatherTargetDeviceSnapshot) {
        let record = BackgroundShortcutTransferRecord(
            jobID: UUID().uuidString,
            targetDeviceID: snapshot.id,
            targetDeviceName: snapshot.name,
            phase: .preparing,
            lastEvent: "准备后台快捷指令任务",
            startedAt: Date(),
            finishedAt: nil,
            errorMessage: nil
        )
        lastBackgroundShortcutTransfer = record
        persistBackgroundShortcutTransferRecord(record)
    }

    func updateBackgroundShortcutTransferRecord(
        phase: BackgroundShortcutTransferPhase,
        errorMessage: String? = nil,
        lastEvent: String? = nil,
        finish: Bool = false
    ) {
        guard var record = lastBackgroundShortcutTransfer else { return }
        record.phase = phase
        if let lastEvent {
            record.lastEvent = lastEvent
        }
        record.errorMessage = errorMessage
        if finish {
            record.finishedAt = Date()
        }
        lastBackgroundShortcutTransfer = record
        persistBackgroundShortcutTransferRecord(record)
    }

    func persistBackgroundShortcutTransferRecord(_ record: BackgroundShortcutTransferRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: BleDiagnosticsStorage.backgroundShortcutTransferKey)
    }
}
