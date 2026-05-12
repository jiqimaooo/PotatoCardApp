//
//  PendingCardPushQueue.swift
//  potato card
//
//  后台快捷指令在没扫到设备/扫描超时时把任务持久化下来，
//  等下次 App 回到前台再统一重推。
//  - 任务图片体积可能不小（成品图 + 传输图），所以保存到 Caches/PendingCardPush/。
//  - 索引存到 Caches 里的 JSON 文件，全部 nonisolated 以便 AppIntent 进程也能调用。
//

import Foundation
import OSLog
import UIKit

struct PendingCardPushTask: Codable, Identifiable, Equatable {
    let id: UUID
    let displayImageFileName: String
    let transferImageFileName: String
    let snapshotData: Data
    let algorithmRaw: String?
    let defaultTitle: String
    let createdAt: Date
}

enum PendingCardPushQueue {
    private static let folderName = "PendingCardPush"
    private static let indexFileName = "pending-card-push.json"
    nonisolated private static let logger = Logger(
        subsystem: "com.xiaogousi.online.potato-card",
        category: "PendingCardPushQueue"
    )

    nonisolated static func enqueue(
        displayImage: UIImage,
        transferImage: UIImage,
        snapshot: WeatherTargetDeviceSnapshot,
        algorithm: EInkDitherAlgorithm,
        defaultTitle: String
    ) -> PendingCardPushTask? {
        guard
            let displayData = displayImage.jpegData(compressionQuality: 0.92),
            let transferData = transferImage.pngData()
        else {
            logger.error("待推送任务保存失败：图片编码失败。")
            return nil
        }

        guard let snapshotData = try? JSONEncoder().encode(snapshot) else {
            logger.error("待推送任务保存失败：snapshot 编码失败。")
            return nil
        }

        let id = UUID()
        let displayName = "\(id.uuidString)-display.jpg"
        let transferName = "\(id.uuidString)-transfer.png"

        do {
            try ensureFolderExists()
            try displayData.write(to: folderURL.appendingPathComponent(displayName), options: .atomic)
            try transferData.write(to: folderURL.appendingPathComponent(transferName), options: .atomic)
        } catch {
            logger.error("待推送任务保存失败：写盘失败 \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let task = PendingCardPushTask(
            id: id,
            displayImageFileName: displayName,
            transferImageFileName: transferName,
            snapshotData: snapshotData,
            algorithmRaw: algorithm.rawValue,
            defaultTitle: defaultTitle,
            createdAt: Date()
        )

        var tasks = loadAll()
        tasks.append(task)
        saveIndex(tasks)
        ShortcutDebugLog.log("PendingQueue", "enqueue id=\(id) target=\(snapshot.id) title=\(defaultTitle)")
        return task
    }

    nonisolated static func loadAll() -> [PendingCardPushTask] {
        guard
            let data = try? Data(contentsOf: indexFileURL),
            let tasks = try? JSONDecoder().decode([PendingCardPushTask].self, from: data)
        else {
            return []
        }
        return tasks
    }

    nonisolated static func remove(id: UUID) {
        var tasks = loadAll()
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }

        let task = tasks.remove(at: index)
        try? FileManager.default.removeItem(at: folderURL.appendingPathComponent(task.displayImageFileName))
        try? FileManager.default.removeItem(at: folderURL.appendingPathComponent(task.transferImageFileName))
        saveIndex(tasks)
        ShortcutDebugLog.log("PendingQueue", "remove id=\(id) remaining=\(tasks.count)")
    }

    nonisolated static func loadImages(for task: PendingCardPushTask) -> (display: UIImage, transfer: UIImage)? {
        let displayURL = folderURL.appendingPathComponent(task.displayImageFileName)
        let transferURL = folderURL.appendingPathComponent(task.transferImageFileName)

        guard
            let displayData = try? Data(contentsOf: displayURL),
            let displayImage = UIImage(data: displayData),
            let transferData = try? Data(contentsOf: transferURL),
            let transferImage = UIImage(data: transferData)
        else {
            return nil
        }
        return (displayImage, transferImage)
    }

    nonisolated static func loadSnapshot(for task: PendingCardPushTask) -> WeatherTargetDeviceSnapshot? {
        try? JSONDecoder().decode(WeatherTargetDeviceSnapshot.self, from: task.snapshotData)
    }

    nonisolated private static func saveIndex(_ tasks: [PendingCardPushTask]) {
        do {
            try ensureFolderExists()
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            logger.error("待推送任务索引写盘失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated private static func ensureFolderExists() throws {
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    nonisolated private static var folderURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }

    nonisolated private static var indexFileURL: URL {
        folderURL.appendingPathComponent(indexFileName)
    }
}
