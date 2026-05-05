import Combine
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

enum BleTransferError: LocalizedError {
    case bluetoothUnavailable(String)
    case transferBusy
    case deviceNotReady
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
        case .deviceNotFound(let name):
            return "没有扫描到设备 \(name)，请确认设备已开机并在附近。"
        case .transferFailed(let message):
            return message
        case .transferTimedOut:
            return "设备传输超时，请重试。"
        case .bluetoothReadyTimedOut:
            return "蓝牙状态初始化超时，请确认蓝牙已开启后重试。"
        case .backgroundTimeExpired:
            return "系统后台运行时间已结束，本次天气推送未完成。"
        }
    }
}

private enum BleTransferPresentationMode {
    case interactive
    case backgroundShortcut
}

// SDK 回调会把原始设备字典从后台线程带回主线程，这里用一个受控的桥接盒子收口并发边界。
private final class BlePayloadBox: @unchecked Sendable {
    let payload: [AnyHashable: Any]

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
    private var wantsForegroundAutoScan = false
    private let transferredImageStore = TransferredDeviceImageStore()
    private let liveTransferActivity = LiveTransferActivityController()
    private var transferBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var transferPresentationMode: BleTransferPresentationMode = .interactive
    private var automatedPushContinuation: CheckedContinuation<BleDevice, Error>?
    private var automatedTargetDeviceID: String?
    private var automatedMatchedDevice: BleDevice?
    private var automatedPushImage: UIImage?

    init(forcePreviewPrompt: Bool = false) {
        rememberedDeviceIDs = Set(UserDefaults.standard.stringArray(forKey: Self.rememberedDeviceIDsKey) ?? [])
        devices = [
            BleDevice(rawDevice: [
                "name": "NEMR92957953",
                "address": "PREVIEW-DEVICE",
                "power": 82
            ])
        ]
        selectedDevice = devices.first
        if forcePreviewPrompt {
            proximityPromptDevice = devices.first
        }
    }

    func beginForegroundAutoScan() {
        guard !isTransferInProgress else { return }
        wantsForegroundAutoScan = true
        guard bluetoothState.canScan else { return }
        startScan()
    }

    func startScan() {
        guard !isTransferInProgress else { return }
        errorMessage = nil
        isScanning = true
        presentPromptIfNeeded(for: devices.first)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.isScanning = false
            if self.devices.isEmpty {
                self.devices = [
                    BleDevice(rawDevice: [
                        "name": "NEMR92957953",
                        "address": "PREVIEW-DEVICE",
                        "power": 82
                    ])
                ]
                self.selectedDevice = self.devices.first
            }
            self.presentPromptIfNeeded(for: self.devices.first)
        }
    }

    func stopScan() {
        wantsForegroundAutoScan = false
        isScanning = false
    }

    func handleSceneBecameActive() {
        guard !isTransferInProgress else { return }
        beginForegroundAutoScan()
    }

    func handleSceneEnteredBackground() {
        wantsForegroundAutoScan = false
        guard !isTransferInProgress else { return }
        stopScan()
    }

    func select(_ device: BleDevice) {
        selectedDevice = device
        syncLastTransferredImage(for: device)
    }

    func connect(_ device: BleDevice) {
        stopScan()
        selectedDevice = device
        connectionPhase = .connecting

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.connectedDevice = device
            self.selectedDevice = device
            self.connectionPhase = .connected
            self.rememberDevice(device)
            self.syncLastTransferredImage(for: device)

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
        if connectionPhase != .connected {
            connectionPhase = .idle
        }
    }

    func transfer(image: UIImage, to device: BleDevice) {
        selectedDevice = device
        currentAddress = device.address
        transferPhase = .transferring
        transferProgress = 0.35
        beginTransferAuxiliaryWorkIfNeeded(for: device.name)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.transferProgress = 1
            self.transferPhase = .succeeded
            self.endTransferAuxiliaryWorkIfNeeded(finalPhaseTitle: self.transferPhase.title)
            self.finishAutomatedPush(with: .success(device))
        }
    }

    func pushWeatherImage(_ image: UIImage, toTargetDeviceSnapshot snapshot: WeatherTargetDeviceSnapshot) async throws -> BleDevice {
        logger.info("模拟器环境开始天气推送：targetID=\(snapshot.id, privacy: .public), name=\(snapshot.name, privacy: .public)")
        transferPresentationMode = .backgroundShortcut
        guard !snapshot.id.trimmed.isEmpty else {
            logger.error("模拟器环境天气推送失败：目标设备信息不完整。")
            throw BleTransferError.deviceNotReady
        }

        guard !isTransferInProgress, automatedPushContinuation == nil else {
            logger.error("模拟器环境天气推送失败：当前已有传输任务。")
            throw BleTransferError.transferBusy
        }

        guard let device = devices.first(where: { $0.id == snapshot.id }) ?? selectedDevice ?? devices.first else {
            logger.error("模拟器环境天气推送失败：没有找到可用设备。")
            throw BleTransferError.deviceNotFound(snapshot.name)
        }

        automatedTargetDeviceID = snapshot.id
        automatedMatchedDevice = device

        return try await withCheckedThrowingContinuation { continuation in
            automatedPushContinuation = continuation
            // 后台快捷指令在开始扫描/连接前就申请执行时间，避免尚未传输就被挂起。
            beginTransferBackgroundTask()
            transfer(image: image, to: device)
        }
    }

    func startWeatherImagePush(_ image: UIImage, toTargetDeviceSnapshot snapshot: WeatherTargetDeviceSnapshot) async throws {
        logger.info("模拟器环境启动天气推送：targetID=\(snapshot.id, privacy: .public), name=\(snapshot.name, privacy: .public)")
        transferPresentationMode = .backgroundShortcut

        guard !snapshot.id.trimmed.isEmpty else {
            transferPresentationMode = .interactive
            throw BleTransferError.deviceNotReady
        }

        guard !isTransferInProgress, automatedPushContinuation == nil, automatedPushImage == nil else {
            transferPresentationMode = .interactive
            throw BleTransferError.transferBusy
        }

        guard let device = devices.first(where: { $0.id == snapshot.id }) ?? selectedDevice ?? devices.first else {
            transferPresentationMode = .interactive
            throw BleTransferError.deviceNotFound(snapshot.name)
        }

        automatedTargetDeviceID = snapshot.id
        automatedMatchedDevice = device
        automatedPushImage = image
        // 后台快捷指令在开始扫描/连接前就申请执行时间，避免尚未传输就被挂起。
        beginTransferBackgroundTask()
        transfer(image: image, to: device)
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

    private func finishAutomatedPush(with result: Result<BleDevice, Error>) {
        let continuation = automatedPushContinuation
        automatedPushContinuation = nil
        automatedTargetDeviceID = nil
        automatedMatchedDevice = nil
        automatedPushImage = nil
        // 模拟器也保持同样的收尾语义，避免预览调试时留下后台任务。
        endTransferBackgroundTask()
        transferPresentationMode = .interactive

        switch result {
        case .success(let device):
            transferProgress = 1
            transferPhase = .succeeded
            continuation?.resume(returning: device)
        case .failure(let error):
            transferPhase = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
            continuation?.resume(throwing: error)
        }
    }

    // 快捷指令后台运行不能依赖 Live Activity，但仍需要后台任务承载 BLE 传输窗口。
    private func beginTransferAuxiliaryWorkIfNeeded(for deviceName: String) {
        beginTransferBackgroundTask()
        guard transferPresentationMode == .interactive else { return }
        liveTransferActivity.start(deviceName: deviceName)
        liveTransferActivity.update(progress: transferProgress, phaseTitle: transferPhase.title)
    }

    private func endTransferAuxiliaryWorkIfNeeded(finalPhaseTitle: String) {
        if transferPresentationMode == .interactive {
            liveTransferActivity.end(progress: transferProgress, phaseTitle: finalPhaseTitle)
        }
        endTransferBackgroundTask()
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
    private var wantsForegroundAutoScan = false

    private lazy var manager = PickBleManager.shared()
    private let transferredImageStore = TransferredDeviceImageStore()
    private let liveTransferActivity = LiveTransferActivityController()
    private var transferBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var didStartManagerWork = false
    private var transferPresentationMode: BleTransferPresentationMode = .interactive
    private var automatedPushContinuation: CheckedContinuation<BleDevice, Error>?
    private var automatedPushImage: UIImage?
    private var automatedTargetSnapshot: WeatherTargetDeviceSnapshot?
    private var automatedMatchedDevice: BleDevice?
    private var automatedScanTimeoutTask: Task<Void, Never>?
    private var automatedTransferTimeoutTask: Task<Void, Never>?
    private var transferBackgroundTask: BleBackgroundTaskBox?

    override init() {
        rememberedDeviceIDs = Set(UserDefaults.standard.stringArray(forKey: Self.rememberedDeviceIDsKey) ?? [])
        super.init()
    }

    convenience init(forcePreviewPrompt: Bool) {
        self.init()
    }

    func beginForegroundAutoScan() {
        ensureManagerStarted()
        guard !isTransferInProgress else { return }
        wantsForegroundAutoScan = true
        guard bluetoothState.canScan else { return }
        startScan()
    }

    func startScan() {
        ensureManagerStarted()
        guard !isTransferInProgress else { return }
        guard bluetoothState.canScan else {
            logger.notice("蓝牙未就绪，跳过本次扫描请求：\(self.bluetoothState.title, privacy: .public)")
            return
        }
        errorMessage = nil
        devices.removeAll()
        selectedDevice = connectedDevice
        isScanning = true
        manager.stopScan()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.manager.startScan()
        }
    }

    func stopScan() {
        wantsForegroundAutoScan = false
        isScanning = false
        guard bluetoothState.canScan else { return }
        manager.stopScan()
    }

    func handleSceneBecameActive() {
        guard !isTransferInProgress else { return }
        beginForegroundAutoScan()
    }

    func handleSceneEnteredBackground() {
        wantsForegroundAutoScan = false
        guard !isTransferInProgress else { return }
        stopScan()
    }

    func select(_ device: BleDevice) {
        selectedDevice = device
        syncLastTransferredImage(for: device)
    }

    func connect(_ device: BleDevice) {
        stopScan()
        selectedDevice = device
        connectionPhase = .connecting

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.connectedDevice = device
            self.selectedDevice = device
            self.connectionPhase = .connected
            self.rememberDevice(device)
            self.syncLastTransferredImage(for: device)

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
        if connectionPhase != .connected {
            connectionPhase = .idle
        }
    }

    func transfer(image: UIImage, to device: BleDevice) {
        resetAutomatedPushStateForInteractiveTransfer()
        performTransfer(image: image, to: device, presentationMode: .interactive)
    }

    private func performTransfer(image: UIImage, to device: BleDevice, presentationMode: BleTransferPresentationMode) {
        ensureManagerStarted()
        guard !isTransferInProgress else {
            errorMessage = BleTransferError.transferBusy.localizedDescription
            return
        }

        guard bluetoothState.canScan else {
            let message = BleTransferError.bluetoothUnavailable(bluetoothState.title).localizedDescription
            transferPhase = .failed(message)
            errorMessage = message
            return
        }

        // 优先使用扫描列表里的新设备对象，避免长时间停留后把过期 rawDevice 传给 SDK。
        let transferDevice = freshestDevice(for: device)
        transferPresentationMode = presentationMode
        selectedDevice = transferDevice
        transferPhase = .preparing
        transferProgress = 0
        currentBlock = 0
        currentAddress = transferDevice.address
        errorMessage = nil
        beginTransferAuxiliaryWorkIfNeeded(for: transferDevice.name)

        manager.updateImage(withDevice: transferDevice.rawDevice, image: image)
    }

    func pushWeatherImage(_ image: UIImage, toTargetDeviceSnapshot snapshot: WeatherTargetDeviceSnapshot) async throws -> BleDevice {
        ensureManagerStarted()
        logger.info("开始蓝牙天气推送：targetID=\(snapshot.id, privacy: .public), name=\(snapshot.name, privacy: .public)")
        transferPresentationMode = .backgroundShortcut

        do {
            try await waitForBluetoothReadyIfNeeded()
        } catch {
            logger.error("蓝牙天气推送失败：蓝牙状态不可用，state=\(self.bluetoothState.title, privacy: .public)")
            transferPresentationMode = .interactive
            throw error
        }

        guard !isTransferInProgress, automatedPushContinuation == nil else {
            logger.error("蓝牙天气推送失败：当前已有传输任务。")
            transferPresentationMode = .interactive
            throw BleTransferError.transferBusy
        }

        guard !snapshot.id.trimmed.isEmpty else {
            logger.error("蓝牙天气推送失败：目标设备信息不完整。")
            transferPresentationMode = .interactive
            throw BleTransferError.deviceNotReady
        }

        automatedPushImage = image
        automatedTargetSnapshot = snapshot

        return try await withCheckedThrowingContinuation { continuation in
            automatedPushContinuation = continuation
            // 后台快捷指令在开始扫描/连接前就申请执行时间，避免尚未传输就被挂起。
            beginTransferBackgroundTask()

            if let device = self.connectedDevice, self.device(device, matches: snapshot) {
                self.logger.info("目标设备当前已连接，直接开始传输。")
                self.startAutomatedTransfer(to: device)
                return
            }

            if let device = self.devices.first(where: { self.device($0, matches: snapshot) }) {
                self.logger.info("使用当前会话里缓存的目标设备，避免后台重新扫描失败。")
                self.startAutomatedTransfer(to: device)
                return
            }

            // 没有可用缓存时再扫描，后台扫描可能被系统限制。
            self.logger.info("后台运行或未命中当前会话，开始自动扫描目标设备。")
            self.startAutomatedScan(for: snapshot)
        }
    }

    func startWeatherImagePush(_ image: UIImage, toTargetDeviceSnapshot snapshot: WeatherTargetDeviceSnapshot) async throws {
        ensureManagerStarted()
        logger.info("启动蓝牙天气推送：targetID=\(snapshot.id, privacy: .public), name=\(snapshot.name, privacy: .public)")
        transferPresentationMode = .backgroundShortcut

        do {
            try await waitForBluetoothReadyIfNeeded()
        } catch {
            logger.error("蓝牙天气推送启动失败：蓝牙状态不可用，state=\(self.bluetoothState.title, privacy: .public)")
            transferPresentationMode = .interactive
            throw error
        }

        guard !isTransferInProgress, automatedPushContinuation == nil, automatedPushImage == nil else {
            logger.error("蓝牙天气推送启动失败：当前已有传输任务。")
            transferPresentationMode = .interactive
            throw BleTransferError.transferBusy
        }

        guard !snapshot.id.trimmed.isEmpty else {
            logger.error("蓝牙天气推送启动失败：目标设备信息不完整。")
            transferPresentationMode = .interactive
            throw BleTransferError.deviceNotReady
        }

        automatedPushImage = image
        automatedTargetSnapshot = snapshot
        // 后台快捷指令在开始扫描/连接前就申请执行时间，避免尚未传输就被挂起。
        beginTransferBackgroundTask()

        if let device = connectedDevice, self.device(device, matches: snapshot) {
            logger.info("目标设备当前已连接，启动后立即返回快捷指令。")
            startAutomatedTransfer(to: device)
            return
        }

        if let device = devices.first(where: { self.device($0, matches: snapshot) }) {
            logger.info("使用当前会话里缓存的目标设备，避免后台重新扫描失败。")
            startAutomatedTransfer(to: device)
            return
        }

        // 没有可用缓存时再扫描，后台扫描可能被系统限制。
        logger.info("后台运行或未命中当前会话，启动自动扫描目标设备。")
        startAutomatedScan(for: snapshot)
    }

    nonisolated func didBluetoothStatusNotification(_ state: Int) {
        Task { @MainActor in
            self.bluetoothState = BlePowerState(sdkState: state)

            if !self.bluetoothState.canScan {
                self.isScanning = false
                if self.hasAutomatedPush, !self.isTransferInProgress {
                    self.finishAutomatedPush(with: .failure(BleTransferError.bluetoothUnavailable(self.bluetoothState.title)))
                }
            } else if self.wantsForegroundAutoScan && !self.isScanning && self.connectedDevice == nil {
                self.startScan()
            }
        }
    }

    nonisolated func bluetoothSearchDevice(_ device: [AnyHashable: Any]) {
        let payloadBox = BlePayloadBox(payload: device)

        Task { @MainActor in
            let bleDevice = BleDevice(rawDevice: payloadBox.payload)

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
                let percent = (device["percent"] as? NSNumber)?.doubleValue ?? device["percent"] as? Double ?? 0
                let block = (device["currentBlock"] as? NSNumber)?.intValue ?? device["currentBlock"] as? Int ?? 0
                let normalizedPercent = percent > 1 ? percent / 100 : percent
                self.logger.info("收到蓝牙传输进度：percent=\(normalizedPercent, privacy: .public), block=\(block, privacy: .public)")

                self.currentAddress = address
                self.currentBlock = block
                self.transferProgress = min(max(normalizedPercent, 0), 1)
                self.transferPhase = .transferring
                if self.transferPresentationMode == .interactive {
                    self.liveTransferActivity.update(progress: self.transferProgress, phaseTitle: self.transferPhase.title)
                }
                return
            }

            guard type == 1 else { return }

            let status = (device["status"] as? NSNumber)?.intValue ?? device["status"] as? Int ?? -1
            self.currentAddress = address
            self.logger.info("收到蓝牙传输状态：status=\(status, privacy: .public), address=\(address, privacy: .public)")

            switch status {
            case 3:
                self.transferPhase = .failed("传输出错")
                self.errorMessage = "设备 \(address.isEmpty ? "未知" : address) 传输出错，请重试。"
                self.endTransferAuxiliaryWorkIfNeeded(finalPhaseTitle: "传输失败")
                self.finishAutomatedPush(with: .failure(BleTransferError.transferFailed(self.errorMessage ?? "设备传输出错，请重试。")))
            case 4:
                self.transferProgress = max(self.transferProgress, 0.01)
                self.transferPhase = .transferring
                if self.transferPresentationMode == .interactive {
                    self.liveTransferActivity.update(progress: self.transferProgress, phaseTitle: self.transferPhase.title)
                }
            case 5:
                self.transferProgress = 1
                self.transferPhase = .succeeded
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

    private func startAutomatedScan(for snapshot: WeatherTargetDeviceSnapshot) {
        logger.info("开始自动扫描设备：\(snapshot.name, privacy: .public)")
        errorMessage = nil
        automatedMatchedDevice = nil
        devices.removeAll()
        selectedDevice = nil
        isScanning = true
        if bluetoothState.canScan {
            manager.stopScan()
        }

        automatedScanTimeoutTask?.cancel()
        automatedScanTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard let self, self.hasAutomatedPush, self.automatedMatchedDevice == nil else { return }
            if self.bluetoothState.canScan {
                self.manager.stopScan()
            }
            self.isScanning = false
            self.logger.error("自动扫描超时：\(snapshot.name, privacy: .public)")
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
        automatedScanTimeoutTask?.cancel()
        automatedScanTimeoutTask = nil
        automatedMatchedDevice = device
        isScanning = false
        if bluetoothState.canScan {
            manager.stopScan()
        }
        performTransfer(image: image, to: device, presentationMode: .backgroundShortcut)

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
        automatedPushContinuation = nil
        automatedPushImage = nil
        automatedTargetSnapshot = nil
        automatedMatchedDevice = nil
        automatedScanTimeoutTask?.cancel()
        automatedScanTimeoutTask = nil
        automatedTransferTimeoutTask?.cancel()
        automatedTransferTimeoutTask = nil
        // 自动推送由快捷指令驱动，完成或失败时必须释放后台任务和 UI 状态。
        endTransferBackgroundTask()
        transferPresentationMode = .interactive

        switch result {
        case .success(let device):
            logger.info("自动推送完成：\(device.name, privacy: .public)")
            transferProgress = 1
            transferPhase = .succeeded
            continuation?.resume(returning: device)
        case .failure(let error):
            logger.error("自动推送失败：\(error.localizedDescription, privacy: .public)")
            transferPhase = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
            continuation?.resume(throwing: error)
        }
    }

    private func resetAutomatedPushStateForInteractiveTransfer() {
        guard hasAutomatedPush || transferPresentationMode != .interactive else { return }

        automatedPushContinuation?.resume(throwing: BleTransferError.transferBusy)
        automatedPushContinuation = nil
        automatedPushImage = nil
        automatedTargetSnapshot = nil
        automatedMatchedDevice = nil
        automatedScanTimeoutTask?.cancel()
        automatedScanTimeoutTask = nil
        automatedTransferTimeoutTask?.cancel()
        automatedTransferTimeoutTask = nil
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
        manager.delegate = self
        manager.startWork()
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

    // 快捷指令后台运行不能请求 Live Activity，但仍需要后台任务承载 BLE 传输窗口。
    private func beginTransferAuxiliaryWorkIfNeeded(for deviceName: String) {
        beginTransferBackgroundTask()
        guard transferPresentationMode == .interactive else { return }
        liveTransferActivity.start(deviceName: deviceName)
        liveTransferActivity.update(progress: 0, phaseTitle: transferPhase.title)
    }

    private func endTransferAuxiliaryWorkIfNeeded(finalPhaseTitle: String) {
        if transferPresentationMode == .interactive {
            liveTransferActivity.end(progress: transferProgress, phaseTitle: finalPhaseTitle)
        }
        endTransferBackgroundTask()
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
        // 已经连上并开始传输后，不主动判失败；CoreBluetooth 后台模式仍可能继续回调传输进度。
        if automatedMatchedDevice != nil || isTransferInProgress {
            logger.notice("UIKit 后台执行时间到期，保留 BLE 传输状态，等待 CoreBluetooth 后台回调。")
            return
        }

        // 如果还没发现目标设备，扫描阶段基本无法在后台继续稳定推进，直接给出明确失败。
        finishAutomatedPush(with: .failure(BleTransferError.backgroundTimeExpired))
    }
}
#endif
