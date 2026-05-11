//
//  HealthSkillPushCoordinator.swift
//  potato card
//
//  健康看板的推送协调器：组装 HealthDataService + HealthSkillRenderer + BleTransferService，
//  与 WeatherSkillPushCoordinator 保持同样的调用形态，方便快捷指令直接拷贝模板。
//

import Foundation
import OSLog
import UIKit

struct HealthPreparedPush {
    let displayImage: UIImage
    let transferImage: UIImage
    let targetDeviceSnapshot: WeatherTargetDeviceSnapshot
    let mode: HealthDashboardMode
}

enum HealthPushError: LocalizedError {
    case skillDisabled
    case missingTargetDevice
    case missingTargetDeviceSnapshot
    case dataUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .skillDisabled:
            return "健康技能已关闭，请先开启后再运行健康推送。"
        case .missingTargetDevice:
            return "请先在 App 里选择墨水屏作为同步设备。"
        case .missingTargetDeviceSnapshot:
            return "目标设备信息不完整，请重新选择同步设备。"
        case .dataUnavailable(let message):
            return message
        }
    }
}

@MainActor
final class HealthSkillPushCoordinator {
    static let shared = HealthSkillPushCoordinator()

    private let bleService: BleTransferService
    private let logger = Logger(subsystem: "com.xiaogousi.online.potato-card", category: "HealthShortcut")

    init() {
        bleService = .shared
    }

    init(bleService: BleTransferService) {
        self.bleService = bleService
    }

    func preparePush(
        snapshot: HealthSnapshot,
        configuration: HealthSkillConfiguration,
        targetDeviceSnapshot: WeatherTargetDeviceSnapshot
    ) -> HealthPreparedPush {
        let displayImage = HealthSkillRenderer.renderDisplayImage(
            snapshot: snapshot,
            targetSize: targetDeviceSnapshot.profile.pixelSize
        )
        let transferImage = EInkImageRenderer.renderForTransfer(
            image: displayImage,
            targetSize: targetDeviceSnapshot.profile.pixelSize,
            fitMode: .centerCrop,
            profile: targetDeviceSnapshot.profile,
            ditherAlgorithm: configuration.imageAlgorithm
        )
        return HealthPreparedPush(
            displayImage: displayImage,
            transferImage: transferImage,
            targetDeviceSnapshot: targetDeviceSnapshot,
            mode: snapshot.mode
        )
    }

    func pushHealthDashboard(mode: HealthDashboardMode, waitForFinalResult: Bool) async throws -> String {
        let store = HealthSkillStore()
        logger.info("开始准备健康推送 mode=\(mode.rawValue, privacy: .public) enabled=\(store.config.isEnabled, privacy: .public)")

        guard store.config.isEnabled else {
            logger.error("健康推送终止：技能已关闭。")
            throw HealthPushError.skillDisabled
        }

        let targetDeviceSnapshot = try resolveTargetDeviceSnapshot(using: store)
        logger.info("已解析目标设备：id=\(targetDeviceSnapshot.id, privacy: .public), size=\(targetDeviceSnapshot.pixelWidth, privacy: .public)x\(targetDeviceSnapshot.pixelHeight, privacy: .public)")

        // 健康数据：快捷指令场景下我们先请求一次合集授权，再抓取目标模式数据。
        let service = HealthDataService.shared
        do {
            try await service.requestAuthorizationForAllModes()
        } catch {
            // 用户拒绝授权时 fetch* 会自然抛 noData，这里仅记录。
            logger.notice("健康授权请求失败：\(error.localizedDescription, privacy: .public)")
        }

        let snapshot: HealthSnapshot
        do {
            switch mode {
            case .sleep:
                snapshot = .sleep(try await service.fetchSleepSnapshot())
            case .fitness:
                snapshot = .fitness(try await service.fetchFitnessSnapshot())
            case .daily:
                snapshot = .daily(try await service.fetchDailySnapshot())
            }
        } catch let healthError as HealthSkillError {
            throw HealthPushError.dataUnavailable(healthError.localizedDescription)
        }

        let prepared = preparePush(
            snapshot: snapshot,
            configuration: store.config,
            targetDeviceSnapshot: targetDeviceSnapshot
        )
        logger.info("健康看板渲染完成，开始推送。")

        let device = try await bleService.pushWeatherImage(
            prepared.transferImage,
            displayImage: prepared.displayImage,
            toTargetDeviceSnapshot: prepared.targetDeviceSnapshot,
            algorithm: store.config.imageAlgorithm,
            returnAfterTransferStarted: !waitForFinalResult
        )
        logger.info("健康看板推送已开始：\(device.name, privacy: .public)")

        store.updateTargetDevice(device)
        store.markSynced(mode: mode)

        if waitForFinalResult {
            bleService.markLastTransferredImage(prepared.displayImage, for: device.id)
            return "已推送\(mode.title)到\(device.name)"
        }
        return "已开始把\(mode.title)推送到\(device.name)，后台会继续传输。"
    }

    private func resolveTargetDeviceSnapshot(using store: HealthSkillStore) throws -> WeatherTargetDeviceSnapshot {
        let targetID = store.config.targetDeviceID.trimmed
        if targetID.isEmpty, let snapshot = store.config.targetDeviceSnapshot {
            logger.notice("健康配置缺 targetDeviceID，使用已保存的快照。")
            store.updateTargetDeviceSnapshot(snapshot)
            return snapshot
        }

        // 健康技能没有自己绑过设备时，沿用天气技能里的同步设备，
        // 与 CardPushCoordinator 行为保持一致，减少“到处都要选一遍设备”的体感。
        if targetID.isEmpty {
            let weatherStore = WeatherSkillStore()
            if let snapshot = weatherStore.config.targetDeviceSnapshot {
                logger.notice("健康配置没有目标设备，复用天气技能的同步设备：\(snapshot.id, privacy: .public)")
                store.updateTargetDeviceSnapshot(snapshot)
                return snapshot
            }
            if let device = bleService.connectedDevice ?? bleService.selectedDevice {
                logger.notice("健康配置没有目标设备，使用当前已连接/选中设备：\(device.id, privacy: .public)")
                store.updateTargetDevice(device)
                return device.targetSnapshot
            }
            throw HealthPushError.missingTargetDevice
        }

        if let snapshot = store.config.targetDeviceSnapshot, snapshot.id == targetID {
            return snapshot
        }

        if let device = liveDevice(for: targetID) {
            let snapshot = device.targetSnapshot
            store.updateTargetDeviceSnapshot(snapshot)
            return snapshot
        }

        throw HealthPushError.missingTargetDeviceSnapshot
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
