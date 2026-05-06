//
//  GalleryCacheStore.swift
//  potato card
//

import Foundation
import UIKit

struct GalleryPhoto: Identifiable, Equatable {
    let id: UUID
    let imageData: Data
    let image: UIImage
    let title: String
}

enum GalleryCacheStore {
    nonisolated private static let folderName = "GalleryPhotoCache"
    nonisolated private static let indexFileName = "gallery-index.json"

    nonisolated static func loadPhotos() -> [GalleryPhoto] {
        let entries = loadEntries()

        return entries.compactMap { entry in
            guard
                let data = try? Data(contentsOf: cacheDirectoryURL.appendingPathComponent(entry.fileName)),
                let image = UIImage(data: data)
            else {
                return nil
            }

            return GalleryPhoto(
                id: entry.id,
                imageData: data,
                image: image,
                title: entry.title
            )
        }
    }

    nonisolated static func appendPhoto(data: Data, title: String) -> GalleryPhoto? {
        guard let image = UIImage(data: data) else { return nil }

        do {
            try ensureCacheDirectoryExists()

            let id = UUID()
            let fileName = "\(id.uuidString).jpg"
            let fileURL = cacheDirectoryURL.appendingPathComponent(fileName)
            try data.write(to: fileURL, options: .atomic)

            var entries = loadEntries()
            entries.insert(GalleryCacheEntry(id: id, fileName: fileName, title: title), at: 0)
            try saveEntries(entries)

            return GalleryPhoto(id: id, imageData: data, image: image, title: title)
        } catch {
            return nil
        }
    }

    nonisolated static func clearAll() {
        try? FileManager.default.removeItem(at: cacheDirectoryURL)
    }

    nonisolated static func deletePhoto(id: UUID) {
        var entries = loadEntries()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }

        let entry = entries.remove(at: index)
        try? FileManager.default.removeItem(at: cacheDirectoryURL.appendingPathComponent(entry.fileName))
        try? saveEntries(entries)
    }

    nonisolated private static func loadEntries() -> [GalleryCacheEntry] {
        guard
            let data = try? Data(contentsOf: indexFileURL),
            let entries = try? JSONDecoder().decode([GalleryCacheEntry].self, from: data)
        else {
            return []
        }

        return entries
    }

    nonisolated private static func saveEntries(_ entries: [GalleryCacheEntry]) throws {
        try ensureCacheDirectoryExists()
        let data = try JSONEncoder().encode(entries)
        try data.write(to: indexFileURL, options: .atomic)
    }

    nonisolated private static func ensureCacheDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: cacheDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    nonisolated private static var cacheDirectoryURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }

    nonisolated private static var indexFileURL: URL {
        cacheDirectoryURL.appendingPathComponent(indexFileName)
    }
}

private struct GalleryCacheEntry: Codable {
    let id: UUID
    let fileName: String
    let title: String
}
