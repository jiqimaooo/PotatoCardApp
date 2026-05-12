// Quick CLI to render the three health dashboards into PNGs.
// Build with:
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios17.0-simulator \
//       -framework UIKit -framework HealthKit \
//       "potato card/Features/Skills/HealthSkillModels.swift" \
//       "potato card/Features/Skills/HealthSkillMockData.swift" \
//       "potato card/Features/Skills/HealthSkillRenderer.swift" \
//       tools/dump_health_renders.swift -o build/dump_health_renders
//
// Run inside an iOS simulator via xcrun simctl spawn.

import UIKit
import Foundation

// Stubs for app types HealthSkillModels.swift references but the renderer doesn't.
enum EInkDitherAlgorithm: String, Codable { case bayer8x8 }
struct WeatherTargetDeviceSnapshot: Codable, Equatable {
    let id: String
    let name: String
    let pixelWidth: Int
    let pixelHeight: Int
}
struct Skill {
    let id: String
    let title: String
    let isEnabled: Bool
    let lastSyncAt: Date?
    let previewSummary: String
    static func weather(summary: String, configuration: Any) -> Skill {
        Skill(id: "w", title: "", isEnabled: false, lastSyncAt: nil, previewSummary: summary)
    }
}

@main
struct DumpMain {
    static func main() {
        let outDir = "/tmp/health-renders"
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        func dump(_ snapshot: HealthSnapshot, name: String) {
            let image = HealthSkillRenderer.renderDisplayImage(snapshot: snapshot, targetSize: CGSize(width: 400, height: 600))
            guard let data = image.pngData() else { return }
            let path = outDir + "/" + name + ".png"
            try? data.write(to: URL(fileURLWithPath: path))
            print("WROTE", path)
        }

        dump(.sleep(HealthSkillMockData.sleep), name: "render-sleep")
        dump(.fitness(HealthSkillMockData.fitness), name: "render-fitness")
        dump(.daily(HealthSkillMockData.daily), name: "render-daily")
    }
}
