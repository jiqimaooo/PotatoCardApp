import Foundation
import OSLog
import UIKit

struct WeatherPreparedPush {
    let displayImage: UIImage
    let transferImage: UIImage
    let targetDeviceSnapshot: WeatherTargetDeviceSnapshot
}

enum WeatherPushError: LocalizedError {
    case skillDisabled
    case missingTargetDevice
    case missingTargetDeviceSnapshot
    case weatherUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .skillDisabled:
            return "天气技能已关闭，请先开启后再运行天气推送。"
        case .missingTargetDevice:
            return "请先在天气技能里选择同步设备。"
        case .missingTargetDeviceSnapshot:
            return "目标设备信息不完整，请在天气技能里重新选择同步设备。"
        case .weatherUnavailable(let message):
            return message
        }
    }
}

@MainActor
final class WeatherSkillPushCoordinator {
    static let shared = WeatherSkillPushCoordinator()

    private let bleService: BleTransferService
    private let logger = Logger(subsystem: "com.xiaogousi.online.potato-card", category: "WeatherShortcut")

    init() {
        bleService = .shared
    }

    init(bleService: BleTransferService) {
        self.bleService = bleService
    }

    // 手动同步和快捷指令都复用同一套天气图生成逻辑。
    func preparePush(
        snapshot: WeatherSkillSnapshot,
        configuration: WeatherSkillConfiguration,
        targetDeviceSnapshot: WeatherTargetDeviceSnapshot
    ) -> WeatherPreparedPush {
        let displayImage = WeatherSkillRenderer.renderDisplayImage(
            snapshot: snapshot,
            template: configuration.template,
            targetSize: targetDeviceSnapshot.profile.pixelSize
        )
        let transferImage = EInkImageRenderer.renderForTransfer(
            image: displayImage,
            targetSize: targetDeviceSnapshot.profile.pixelSize,
            fitMode: .centerCrop,
            profile: targetDeviceSnapshot.profile,
            // 天气模块优先使用自己的图像算法，不跟随全局传输算法。
            ditherAlgorithm: configuration.imageAlgorithm
        )

        return WeatherPreparedPush(
            displayImage: displayImage,
            transferImage: transferImage,
            targetDeviceSnapshot: targetDeviceSnapshot
        )
    }

    func pushLatestWeather() async throws -> String {
        try await pushLatestWeather(waitForFinalResult: true)
    }

    func startLatestWeatherPushFromShortcut() async throws -> String {
        try await pushLatestWeather(waitForFinalResult: false)
    }

    private func pushLatestWeather(waitForFinalResult: Bool) async throws -> String {
        let store = WeatherSkillStore()
        logger.info("开始准备天气推送。技能开关=\(store.config.isEnabled, privacy: .public)")

        guard store.config.isEnabled else {
            logger.error("天气推送终止：天气技能已关闭。")
            throw WeatherPushError.skillDisabled
        }

        let targetDeviceSnapshot = try resolveTargetDeviceSnapshot(using: store)
        logger.info("已解析目标设备：id=\(targetDeviceSnapshot.id, privacy: .public), name=\(targetDeviceSnapshot.name, privacy: .public), size=\(Int(targetDeviceSnapshot.pixelWidth), privacy: .public)x\(Int(targetDeviceSnapshot.pixelHeight), privacy: .public)")

        await store.refreshWeather()
        guard let snapshot = store.snapshot else {
            logger.error("天气推送终止：天气刷新失败，loadState=\(store.loadState.message, privacy: .public)")
            throw WeatherPushError.weatherUnavailable(store.loadState.message)
        }
        logger.info("天气数据刷新成功：location=\(snapshot.location.name, privacy: .public), temp=\(snapshot.current.temperature, privacy: .public)")

        let prepared = preparePush(
            snapshot: snapshot,
            configuration: store.config,
            targetDeviceSnapshot: targetDeviceSnapshot
        )
        logger.info("天气图片渲染完成，准备推送到蓝牙设备。")

        let device = try await bleService.pushWeatherImage(
            prepared.transferImage,
            displayImage: prepared.displayImage,
            toTargetDeviceSnapshot: prepared.targetDeviceSnapshot,
            algorithm: store.config.imageAlgorithm,
            returnAfterTransferStarted: !waitForFinalResult
        )
        logger.info("蓝牙推送已进入目标状态：\(device.name, privacy: .public), waitForFinalResult=\(waitForFinalResult, privacy: .public)")

        store.updateTargetDevice(device)
        if waitForFinalResult {
            bleService.markLastTransferredImage(prepared.displayImage, for: device.id)
            store.markSynced()
            return "已推送到\(device.name)"
        }

        return "已开始传输数据到\(device.name)，后台会继续推送"
    }

    private func resolveTargetDeviceSnapshot(using store: WeatherSkillStore) throws -> WeatherTargetDeviceSnapshot {
        let targetID = store.config.targetDeviceID.trimmed
        // 兼容早期只保存了设备快照、还没把设备标识补齐的配置。
        if targetID.isEmpty, let snapshot = store.config.targetDeviceSnapshot {
            logger.notice("配置里没有 targetDeviceID，但存在设备快照，自动补齐。")
            store.updateTargetDeviceSnapshot(snapshot)
            return snapshot
        }

        guard !targetID.isEmpty else {
            logger.error("天气推送终止：未配置同步设备。")
            throw WeatherPushError.missingTargetDevice
        }

        if let snapshot = store.config.targetDeviceSnapshot, snapshot.id == targetID {
            logger.info("直接使用已保存的设备快照。")
            return snapshot
        }

        if let liveDevice = liveDevice(for: targetID) {
            logger.notice("已从当前蓝牙会话恢复设备快照：\(liveDevice.name, privacy: .public)")
            let snapshot = liveDevice.targetSnapshot
            store.updateTargetDeviceSnapshot(snapshot)
            return snapshot
        }

        logger.error("天气推送终止：设备快照缺失，targetID=\(targetID, privacy: .public)")
        throw WeatherPushError.missingTargetDeviceSnapshot
    }

    private func liveDevice(for targetID: String) -> BleDevice? {
        if let connected = bleService.connectedDevice, connected.id == targetID {
            return connected
        }

        if let selected = bleService.selectedDevice, selected.id == targetID {
            return selected
        }

        return bleService.devices.first(where: { $0.id == targetID })
    }
}
