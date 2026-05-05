import Foundation
import UIKit

struct TransferredDeviceImageStore {
    private let folderName = "TransferredDeviceImages"
    private let latestDeviceIDKey = "latestTransferredDeviceImageID"

    func loadLatestImage() -> UIImage? {
        guard let latestDeviceID = UserDefaults.standard.string(forKey: latestDeviceIDKey) else {
            return nil
        }

        return loadImage(for: latestDeviceID)
    }

    func loadImage(for deviceID: String) -> UIImage? {
        guard
            let fileURL = fileURL(for: deviceID),
            let data = try? Data(contentsOf: fileURL)
        else {
            return nil
        }

        return UIImage(data: data)
    }

    func save(_ image: UIImage, for deviceID: String) {
        guard
            let folderURL = folderURL,
            let fileURL = fileURL(for: deviceID),
            let data = image.jpegData(compressionQuality: 0.92)
        else {
            return
        }

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            // 首页冷启动时需要知道最近一次推送的是哪个设备图。
            UserDefaults.standard.set(deviceID, forKey: latestDeviceIDKey)
        } catch {
            // The screen can still update from memory; disk cache is best-effort.
        }
    }

    private var folderURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private func fileURL(for deviceID: String) -> URL? {
        folderURL?.appendingPathComponent(sanitizedDeviceID(deviceID)).appendingPathExtension("jpg")
    }

    private func sanitizedDeviceID(_ deviceID: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = deviceID.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(scalar) : "_"
        }
        let sanitized = String(scalars)
        return sanitized.isEmpty ? "unknown-device" : sanitized
    }
}
