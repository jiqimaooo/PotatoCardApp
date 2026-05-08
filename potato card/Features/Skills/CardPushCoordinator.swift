//
//  CardPushCoordinator.swift
//  potato card
//
//  土豆片快捷指令的入口协调器：
//  - 解析当前要推送的目标设备（沿用天气技能里绑定好的同步设备）。
//  - 把入参（图片或文字）渲染成设备分辨率的成品图。
//  - 通过 BleTransferService 推送到墨水屏，并把成品图存进 App 图库。
//

import Foundation
import OSLog
import UIKit

enum CardPushError: LocalizedError {
    case missingTargetDevice
    case invalidImage
    case invalidText

    var errorDescription: String? {
        switch self {
        case .missingTargetDevice:
            // 沿用天气技能里的设备绑定；用户没绑定时给出明确指引。
            return "还没有绑定土豆片设备，请先打开 App 在天气技能里选择同步设备。"
        case .invalidImage:
            return "图片解析失败，请重新选择一张图片。"
        case .invalidText:
            return "文字内容为空，无法生成卡片。"
        }
    }
}

@MainActor
final class CardPushCoordinator {
    static let shared = CardPushCoordinator()

    private let bleService: BleTransferService
    private let logger = Logger(subsystem: "com.xiaogousi.online.potato-card", category: "CardPushShortcut")

    // 同 WeatherSkillPushCoordinator 一样拆成两个 init，避免默认参数 .shared 触发 Swift 6 跨 actor 警告。
    init() {
        bleService = .shared
    }

    init(bleService: BleTransferService) {
        self.bleService = bleService
    }

    func pushImage(_ image: UIImage) async throws -> String {
        let snapshot = try resolveTargetDeviceSnapshot()
        logger.info("土豆片图片推送：target=\(snapshot.id, privacy: .public), size=\(snapshot.pixelWidth, privacy: .public)x\(snapshot.pixelHeight, privacy: .public)")

        let displayImage = CardImageRenderer.renderImage(image, targetSize: snapshot.profile.pixelSize)
        let algorithm = bleService.ditherAlgorithm
        // EInkImageRenderer 自己负责 cover 裁切 + 6 色抖动，传源图就够了。
        let transferImage = EInkImageRenderer.renderForTransfer(
            image: image,
            targetSize: snapshot.profile.pixelSize,
            fitMode: .centerCrop,
            profile: snapshot.profile,
            ditherAlgorithm: algorithm
        )

        saveToGallery(displayImage, defaultTitle: "图片卡片")
        return try await pushPrepared(
            displayImage: displayImage,
            transferImage: transferImage,
            snapshot: snapshot,
            algorithm: algorithm
        )
    }

    func pushText(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CardPushError.invalidText }

        let snapshot = try resolveTargetDeviceSnapshot()
        let layout = CardImageRenderer.textLayouts.randomElement() ?? CardImageRenderer.textLayouts[0]
        logger.info("土豆片文字推送：layout=\(layout.name, privacy: .public), length=\(trimmed.count, privacy: .public)")

        let displayImage = CardImageRenderer.renderText(trimmed, targetSize: snapshot.profile.pixelSize, layout: layout)
        let algorithm = bleService.ditherAlgorithm
        let transferImage = EInkImageRenderer.renderForTransfer(
            image: displayImage,
            targetSize: snapshot.profile.pixelSize,
            fitMode: .centerCrop,
            profile: snapshot.profile,
            ditherAlgorithm: algorithm
        )

        let titleSeed = String(trimmed.prefix(18))
        saveToGallery(displayImage, defaultTitle: titleSeed.isEmpty ? "文字卡片" : titleSeed)
        return try await pushPrepared(
            displayImage: displayImage,
            transferImage: transferImage,
            snapshot: snapshot,
            algorithm: algorithm
        )
    }

    private func pushPrepared(
        displayImage: UIImage,
        transferImage: UIImage,
        snapshot: WeatherTargetDeviceSnapshot,
        algorithm: EInkDitherAlgorithm
    ) async throws -> String {
        // 复用天气快捷指令的纯后台传输流程：拿到设备开始接收就返回，
        // 系统后台时间会继续支持完整传输。
        let device = try await bleService.pushWeatherImage(
            transferImage,
            displayImage: displayImage,
            toTargetDeviceSnapshot: snapshot,
            algorithm: algorithm,
            returnAfterTransferStarted: true
        )
        logger.info("土豆片推送已开始：\(device.name, privacy: .public)")
        return "已开始传输到 \(device.name)，后台会继续完成推送。"
    }

    // 设备解析顺序：天气技能里保存的快照 -> 当前蓝牙会话里命中的设备 -> 当前已连接/选中的设备。
    private func resolveTargetDeviceSnapshot() throws -> WeatherTargetDeviceSnapshot {
        let store = WeatherSkillStore()
        if let snapshot = store.config.targetDeviceSnapshot {
            return snapshot
        }

        let targetID = store.config.targetDeviceID.trimmed
        if !targetID.isEmpty {
            if let device = liveDevice(for: targetID) {
                return device.targetSnapshot
            }
        }

        if let device = bleService.connectedDevice ?? bleService.selectedDevice {
            // 没绑定但当前已连接设备时，直接拿当前设备做兜底，避免用户被 App 设置流程卡住。
            return device.targetSnapshot
        }

        throw CardPushError.missingTargetDevice
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

    private func saveToGallery(_ image: UIImage, defaultTitle: String) {
        // JPEG 已经够用，跟 GalleryView 现有的导入路径保持一致。
        guard let data = image.jpegData(compressionQuality: 0.92) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        let title = "\(defaultTitle) · \(formatter.string(from: Date()))"
        _ = GalleryCacheStore.appendPhoto(data: data, title: title)
    }
}
