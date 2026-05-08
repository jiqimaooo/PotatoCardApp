//
//  PotatoCardApp.swift
//  potato card
//
//  Created by wangye on 2026/4/10.
//

import SwiftUI

@main
struct PotatoCardApp: App {
    @StateObject private var bleTransferService = BleTransferService.shared
    @ObservedObject private var weatherAutoUpdateScheduler = WeatherAutoUpdateScheduler.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 最早期装 crash handler；上一次崩溃的堆栈会出现在本次启动日志里。
        CrashLogger.installIfNeeded()
        // BGTaskScheduler.register 必须在 application(_:didFinishLaunching*) 之前调用，
        // 否则会抛 NSInternalInconsistencyException。@main init 是最早可写 Swift 代码的点。
        WeatherAutoUpdateScheduler.registerBackgroundTaskIfNeeded()
        // CBCentralManager 用 RestoreIdentifier 创建时，iOS 会在杀 App 后唤醒时调用 willRestoreState；
        // 必须在 launch 阶段就构造，所以在这里预热（即使开关关着也只是创建一个 idle CBCentralManager）。
        if CardPushPreferences.compatibilityProbeEnabled {
            _ = BackgroundCompatProbe.shared
        }
        ShortcutDebugLog.log("PotatoCardApp", "App.init pid=\(ProcessInfo.processInfo.processIdentifier) thread=\(Thread.isMainThread ? "main" : "bg")")
        // 提前记录一下队列状态，以便判断冷启动时吗 IO 有问题。
        let pending = PendingCardPushQueue.loadAll().count
        ShortcutDebugLog.log("PotatoCardApp", "App.init pending queue count=\(pending)")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleTransferService)
                .onAppear {
                    ShortcutDebugLog.log("PotatoCardApp", "ContentView.onAppear scenePhase=\(String(describing: scenePhase))")
                    weatherAutoUpdateScheduler.handleScenePhase(scenePhase)
                }
                .onChange(of: scenePhase) { phase in
                    ShortcutDebugLog.log("PotatoCardApp", "scenePhase changed -> \(String(describing: phase))")
                    weatherAutoUpdateScheduler.handleScenePhase(phase)
                }
        }
    }
}
