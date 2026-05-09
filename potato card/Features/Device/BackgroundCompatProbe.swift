//
//  BackgroundCompatProbe.swift
//  potato card
//
//  「兼容性增强」实现：
//  - 启动一个独立 CBCentralManager，附带 RestoreIdentifier 让 iOS 可以在杀 App 后唤醒。
//  - 用 service UUID（FEF0）过滤后台扫描，是 iOS 唯一允许的后台 BLE 扫描方式。
//  - 不主动 connect，避免抢占 peripheral 阻塞 PickBleManager；只把发现的设备
//    通过 onDeviceDiscovered 回调喂回去，绕开 SDK 内部失效的无过滤后台扫描。
//

import CoreBluetooth
import Foundation

@MainActor
final class BackgroundCompatProbe: NSObject {
    private static let restoreIdentifier = "com.xiaogousi.online.potato-card.compat-probe"
    private static let inkServiceUUID = CBUUID(string: "FEF0")

    private var centralManager: CBCentralManager?
    private(set) var isRunning = false

    // 扫到目标设备时的回调，BleTransferService 设置。
    var onDeviceDiscovered: ((CBPeripheral, [String: Any], NSNumber) -> Void)?

    // 每个进程共享同一个 manager，以便 iOS 把 willRestoreState 回调发给同一实例。
    static let shared = BackgroundCompatProbe()

    private override init() {
        super.init()
    }

    func start() {
        if centralManager == nil {
            ShortcutDebugLog.log("CompatProbe", "create central with restoreIdentifier")
            centralManager = CBCentralManager(delegate: self, queue: .main, options: [
                CBCentralManagerOptionShowPowerAlertKey: false,
                CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier
            ])
        }

        guard !isRunning else {
            ShortcutDebugLog.log("CompatProbe", "start: already running")
            return
        }
        isRunning = true
        ShortcutDebugLog.log("CompatProbe", "start")

        // 蓝牙就绪时立即开扫描；否则等 didUpdateState 回调里再启动。
        if centralManager?.state == .poweredOn {
            startFilteredScan()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        centralManager?.stopScan()
        ShortcutDebugLog.log("CompatProbe", "stop scan")
    }

    private func startFilteredScan() {
        guard let central = centralManager, central.state == .poweredOn else { return }
        // service UUID 过滤是 iOS 允许的后台扫描方式；后台模式下不允许 nil services。
        central.scanForPeripherals(withServices: [Self.inkServiceUUID], options: nil)
        ShortcutDebugLog.log("CompatProbe", "scanForPeripherals(withServices: FEF0) issued")
    }
}

extension BackgroundCompatProbe: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            ShortcutDebugLog.log("CompatProbe", "central state=\(central.state.rawValue) running=\(self.isRunning)")
            guard self.isRunning, central.state == .poweredOn else { return }
            self.startFilteredScan()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // iOS 在杀 App 后用 RestoreIdentifier 唤醒进程时调用，把之前的扫描/连接传回。
        let scanServices = (dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID])?.map { $0.uuidString } ?? []
        let restoredCount = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.count ?? 0
        Task { @MainActor in
            ShortcutDebugLog.log("CompatProbe", "willRestoreState scanServices=\(scanServices) peripherals=\(restoredCount)")
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            ShortcutDebugLog.log("CompatProbe", "didDiscover \(peripheral.identifier.uuidString) name=\(peripheral.name ?? "nil") rssi=\(RSSI.intValue)")
            self.onDeviceDiscovered?(peripheral, advertisementData, RSSI)
        }
    }
}
