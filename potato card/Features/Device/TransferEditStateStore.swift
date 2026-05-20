import CoreGraphics
import Foundation

enum TransferEditStateKey: Hashable {
    case gallery(UUID)
    case album(String)
    case circle(String)

    var rawValue: String {
        switch self {
        case .gallery(let id):
            return "gallery:\(id.uuidString)"
        case .album(let name):
            return "album:\(name)"
        case .circle(let id):
            return "circle:\(id)"
        }
    }
}

enum TransferEditStateStore {
    // 手动编辑状态按单张图片保存：几何调整 + 可选算法覆盖。
    // algorithmRaw 为空时表示“默认”，即继续跟随我的页面里的全局图像算法。
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
            offsetY: CGFloat(state.offsetY),
            rotation: CGFloat(state.rotation ?? 0)
        )
    }

    static func loadAlgorithmOverride(for key: TransferEditStateKey) -> EInkDitherAlgorithm? {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey(for: key)),
            let state = try? JSONDecoder().decode(StoredTransferEditState.self, from: data),
            let algorithmRaw = state.algorithmRaw
        else {
            return nil
        }

        return EInkDitherAlgorithm(rawValue: algorithmRaw)
    }

    static func save(_ adjustment: EInkManualAdjustment, for key: TransferEditStateKey) {
        save(adjustment, algorithmOverride: loadAlgorithmOverride(for: key), for: key)
    }

    static func saveAdjustmentPreservingAlgorithm(_ adjustment: EInkManualAdjustment, for key: TransferEditStateKey) {
        let algorithmOverride = loadAlgorithmOverride(for: key)
        if adjustment == .default && algorithmOverride == nil {
            delete(for: key)
        } else {
            save(adjustment, algorithmOverride: algorithmOverride, for: key)
        }
    }

    static func hasCustomization(for key: TransferEditStateKey) -> Bool {
        (load(for: key) ?? .default) != .default || loadAlgorithmOverride(for: key) != nil
    }

    static func save(
        _ adjustment: EInkManualAdjustment,
        algorithmOverride: EInkDitherAlgorithm?,
        for key: TransferEditStateKey
    ) {
        let state = StoredTransferEditState(
            scale: Double(adjustment.scale),
            offsetX: Double(adjustment.offsetX),
            offsetY: Double(adjustment.offsetY),
            rotation: Double(adjustment.rotation),
            algorithmRaw: algorithmOverride?.rawValue
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
    // 新增，旧记录缺失时默认 nil → 0 弧度。
    let rotation: Double?
    // 单图算法覆盖。旧记录缺失时为 nil，继续跟随全局算法。
    let algorithmRaw: String?
}
