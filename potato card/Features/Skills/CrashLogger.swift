//
//  CrashLogger.swift
//  potato card
//
//  在 App 启动最早期挂上 NSSetUncaughtExceptionHandler 和常见信号 handler，
//  把未捕获异常 / SIGSEGV / SIGABRT / SIGBUS 等也写到 ShortcutDebugLog 同一份文件里，
//  这样下次重启 App 拉日志时能看到上一次崩溃栈。
//

import Foundation

enum CrashLogger {
    nonisolated(unsafe) private static var didInstall = false

    nonisolated static func installIfNeeded() {
        guard !didInstall else { return }
        didInstall = true

        // NSException handler 不能 capture context（需要 C 函数指针）。把 previous 存到全局变量再调用。
        previousExceptionHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.joined(separator: "\n")
            let reason = exception.reason ?? "<no reason>"
            let name = exception.name.rawValue
            ShortcutDebugLog.log("CRASH", "uncaught NSException name=\(name) reason=\(reason)\nstack:\n\(stack)")
            previousExceptionHandler?(exception)
        }

        let signals: [Int32] = [SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE, SIGPIPE, SIGTRAP]
        for sig in signals {
            signal(sig) { signo in
                // 信号 handler 里只能用 async-signal-safe 调用，但 ShortcutDebugLog 用 dispatch_async
                // 不在 async-signal-safe 列表里，所以写一行精简记录然后立刻 reset+raise，让系统正常 dump。
                let symbols = Thread.callStackSymbols.joined(separator: "\n")
                ShortcutDebugLog.log("CRASH", "signal \(signo)\nstack:\n\(symbols)")
                signal(signo, SIG_DFL)
                raise(signo)
            }
        }

        ShortcutDebugLog.log("CrashLogger", "installed handlers")
    }
}

nonisolated(unsafe) private var previousExceptionHandler: (@convention(c) (NSException) -> Void)? = nil
