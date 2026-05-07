import CoreGraphics
import Foundation

enum TransferEditStateKey: Hashable {
    case gallery(UUID)
    case album(String)

    var rawValue: String {
        switch self {
        case .gallery(let id):
            return "gallery:\(id.uuidString)"
        case .album(let name):
            return "album:\(name)"
        }
    }
}

enum TransferEditStateStore {
    // 手动编辑状态只记录单张图片的缩放和偏移，不绑定图像算法。
    private static let storagePrefix = "transferEditState."

    static func load(for key: TransferEditStateKey) -> EInkManualAdjustment? {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey(for: key)),
            let state = try? JSONDecoder().decode(StoredTransferEditState.self, from: data)
        else {
            return nil
        }

        return EInkManualAdjustment(
            scale: CGFloat(state.scale),
            offsetX: CGFloat(state.offsetX),
            offsetY: CGFloat(state.offsetY)
        )
    }

    static func save(_ adjustment: EInkManualAdjustment, for key: TransferEditStateKey) {
        let state = StoredTransferEditState(
            scale: Double(adjustment.scale),
            offsetX: Double(adjustment.offsetX),
            offsetY: Double(adjustment.offsetY)
        )

        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(for: key))
    }

    static func delete(for key: TransferEditStateKey) {
        UserDefaults.standard.removeObject(forKey: storageKey(for: key))
    }

    private static func storageKey(for key: TransferEditStateKey) -> String {
        storagePrefix + key.rawValue
    }
}

private struct StoredTransferEditState: Codable {
    let scale: Double
    let offsetX: Double
    let offsetY: Double
}
