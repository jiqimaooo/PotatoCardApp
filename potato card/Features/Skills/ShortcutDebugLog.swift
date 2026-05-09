//
//  ShortcutDebugLog.swift
//  potato card
//
//  极简的文件日志，专门用来排查后台快捷指令推送 + 重新打开 App 闪退的问题。
//  写到 Documents/shortcut-debug.log，方便用 devicectl 从设备拉回来分析。
//  全部 nonisolated + 串行队列，AppIntent 后台进程也能安全调用。
//

import Foundation
import OSLog

// 项目默认 SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor，文件级常量也需要显式标 nonisolated 才能在后台调用。
nonisolated private let shortcutDebugLogQueue = DispatchQueue(label: "com.xiaogousi.online.potato-card.shortcut-debug-log")
nonisolated private let shortcutDebugLogger = Logger(subsystem: "com.xiaogousi.online.potato-card", category: "ShortcutDebug")

enum ShortcutDebugLog {
    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated static var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("shortcut-debug.log")
    }

    nonisolated static func log(_ tag: String, _ message: String) {
        let timestamp = formatter.string(from: Date())
        let pid = ProcessInfo.processInfo.processIdentifier
        let processName = ProcessInfo.processInfo.processName
        let line = "[\(timestamp)] [pid=\(pid) \(processName)] [\(tag)] \(message)\n"
        shortcutDebugLogger.info("\(tag, privacy: .public) \(message, privacy: .public)")
        shortcutDebugLogQueue.async {
            appendLine(line)
        }
    }

    nonisolated private static func appendLine(_ line: String) {
        guard let url = fileURL else { return }
        guard let data = line.data(using: .utf8) else { return }

        let fm = FileManager.default
        let maxBytes = 256 * 1024

        if !fm.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
            return
        }

        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue > maxBytes {
            // 满了从头截掉一半，避免无限增长。
            if let existing = try? Data(contentsOf: url) {
                let trimmed = existing.suffix(maxBytes / 2)
                try? trimmed.write(to: url, options: .atomic)
            }
        }

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                // 静默丢弃这条记录，避免后台快捷指令进程因日志写入崩溃。
            }
        }
    }
}
