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
        ShortcutDebugLog.log("CardPushCoordinator", "pushImage start target=\(snapshot.id) size=\(snapshot.pixelWidth)x\(snapshot.pixelHeight)")

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

        if CardPushPreferences.saveImageToGallery {
            saveToGallery(displayImage, defaultTitle: "图片卡片")
        } else {
            ShortcutDebugLog.log("CardPushCoordinator", "pushImage skip gallery save (pref disabled)")
        }
        return try await pushPrepared(
            displayImage: displayImage,
            transferImage: transferImage,
            snapshot: snapshot,
            algorithm: algorithm,
            defaultTitle: "图片卡片"
        )
    }

    func pushText(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CardPushError.invalidText }

        let snapshot = try resolveTargetDeviceSnapshot()
        let layout = CardImageRenderer.textLayouts.randomElement() ?? CardImageRenderer.textLayouts[0]
        logger.info("土豆片文字推送：layout=\(layout.name, privacy: .public), length=\(trimmed.count, privacy: .public)")
        ShortcutDebugLog.log("CardPushCoordinator", "pushText start layout=\(layout.name) length=\(trimmed.count) target=\(snapshot.id)")

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
        let title = titleSeed.isEmpty ? "文字卡片" : titleSeed
        if CardPushPreferences.saveTextToGallery {
            saveToGallery(displayImage, defaultTitle: title)
        } else {
            ShortcutDebugLog.log("CardPushCoordinator", "pushText skip gallery save (pref disabled)")
        }
        return try await pushPrepared(
            displayImage: displayImage,
            transferImage: transferImage,
            snapshot: snapshot,
            algorithm: algorithm,
            defaultTitle: title
        )
    }

    private func pushPrepared(
        displayImage: UIImage,
        transferImage: UIImage,
        snapshot: WeatherTargetDeviceSnapshot,
        algorithm: EInkDitherAlgorithm,
        defaultTitle: String
    ) async throws -> String {
        // 复用天气快捷指令的纯后台传输流程：拿到设备开始接收就返回，
        // 系统后台时间会继续支持完整传输。
        ShortcutDebugLog.log("CardPushCoordinator", "pushPrepared call BLE pushWeatherImage target=\(snapshot.id)")
        do {
            let device = try await bleService.pushWeatherImage(
                transferImage,
                displayImage: displayImage,
                toTargetDeviceSnapshot: snapshot,
                algorithm: algorithm,
                returnAfterTransferStarted: true
            )
            logger.info("土豆片推送已开始：\(device.name, privacy: .public)")
            ShortcutDebugLog.log("CardPushCoordinator", "pushPrepared BLE returned device=\(device.name)")
            return "已开始传输到 \(device.name)，后台会继续完成推送。"
        } catch let bleError as BleTransferError {
            ShortcutDebugLog.log("CardPushCoordinator", "pushPrepared BLE threw: \(bleError.localizedDescription)")
            // 后台冷启动状态下众多原因扫不到设备（设备广播间隔 / iOS 后台限制 / CoreBluetooth 冷启动）。
            // 这种失败不报错，转为入队等待下次 App 前台重推，保证图片不丢且最终能推送。
            switch bleError {
            case .deviceNotFound, .bluetoothReadyTimedOut, .backgroundTimeExpired, .transferTimedOut, .bluetoothUnavailable:
                guard CardPushPreferences.autoSyncPendingPush else {
                    ShortcutDebugLog.log("CardPushCoordinator", "pushPrepared skip enqueue (pref disabled)")
                    throw bleError
                }
                if PendingCardPushQueue.enqueue(
                    displayImage: displayImage,
                    transferImage: transferImage,
                    snapshot: snapshot,
                    algorithm: algorithm,
                    defaultTitle: defaultTitle
                ) != nil {
                    return "已保存到图库；下次打开 App 会自动同步到 \(snapshot.name)。"
                }
                throw bleError
            default:
                throw bleError
            }
        } catch {
            ShortcutDebugLog.log("CardPushCoordinator", "pushPrepared BLE threw: \(error.localizedDescription)")
            throw error
        }
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
        let saved = GalleryCacheStore.appendPhoto(data: data, title: title)
        ShortcutDebugLog.log("CardPushCoordinator", "saveToGallery title=\(title) ok=\(saved != nil)")
    }

    private var isFlushingPendingTasks = false

    // App 回到前台时调用：把后台快捷指令排队但没推成功的任务一一重推。
    // 前台 BLE 扫描可靠性远高于后台 30s 预算 + AppIntent 进程 BLE 冷启动。
    func flushPendingTasksIfNeeded() async {
        guard CardPushPreferences.autoSyncPendingPush else {
            ShortcutDebugLog.log("CardPushCoordinator", "flushPendingTasks skip: pref disabled")
            return
        }
        if isFlushingPendingTasks {
            ShortcutDebugLog.log("CardPushCoordinator", "flushPendingTasks skip: already running")
            return
        }
        let tasks = PendingCardPushQueue.loadAll()
        guard !tasks.isEmpty else { return }
        isFlushingPendingTasks = true
        defer { isFlushingPendingTasks = false }
        ShortcutDebugLog.log("CardPushCoordinator", "flushPendingTasks count=\(tasks.count)")
        logger.info("处理待推送队列：\(tasks.count, privacy: .public) 个任务")

        for task in tasks {
            guard let images = PendingCardPushQueue.loadImages(for: task),
                  let snapshot = PendingCardPushQueue.loadSnapshot(for: task) else {
                ShortcutDebugLog.log("CardPushCoordinator", "flushPendingTasks drop corrupt id=\(task.id)")
                PendingCardPushQueue.remove(id: task.id)
                continue
            }

            let algorithm = task.algorithmRaw.flatMap(EInkDitherAlgorithm.init(rawValue:)) ?? bleService.ditherAlgorithm

            do {
                let device = try await bleService.pushWeatherImage(
                    images.transfer,
                    displayImage: images.display,
                    toTargetDeviceSnapshot: snapshot,
                    algorithm: algorithm,
                    returnAfterTransferStarted: false
                )
                logger.info("待推送任务推送完成：\(device.name, privacy: .public)")
                ShortcutDebugLog.log("CardPushCoordinator", "flushPendingTasks success id=\(task.id) device=\(device.name)")
                PendingCardPushQueue.remove(id: task.id)
            } catch {
                ShortcutDebugLog.log("CardPushCoordinator", "flushPendingTasks failed id=\(task.id) err=\(error.localizedDescription); will retry next time")
                logger.error("待推送任务前台重推失败：\(error.localizedDescription, privacy: .public)；保留待下次")
                // 失败的任务保留在队列里，下次再试。
                return
            }
        }
    }
}
