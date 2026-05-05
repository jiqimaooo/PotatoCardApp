import ActivityKit
import Foundation

struct TransferActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let progress: Double
        let phaseTitle: String

        var percentText: String {
            "\(Int((min(max(progress, 0), 1) * 100).rounded()))%"
        }

        var isSucceeded: Bool {
            progress >= 1 || phaseTitle == "传输成功"
        }
    }

    let deviceName: String
}
