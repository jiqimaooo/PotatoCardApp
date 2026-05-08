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
    @StateObject private var weatherAutoUpdateScheduler = WeatherAutoUpdateScheduler()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleTransferService)
                .onAppear {
                    weatherAutoUpdateScheduler.handleScenePhase(scenePhase)
                }
                .onChange(of: scenePhase) { phase in
                    weatherAutoUpdateScheduler.handleScenePhase(phase)
                }
        }
    }
}
