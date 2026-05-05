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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleTransferService)
        }
    }
}
