import Foundation

struct CircleUserProfile: Codable, Equatable, Identifiable {
    let id: String
    let username: String
    let avatarKey: String
}

struct CirclePost: Codable, Equatable, Identifiable {
    struct Author: Codable, Equatable {
        let id: String
        let username: String
        let avatarKey: String
    }

    let id: String
    let title: String
    let author: Author
    let tags: [String]
    let lockedPreviewStyle: String
    let targetWidth: Int?
    let targetHeight: Int?
    let colorMode: String?
    let transferCount: Int
    let createdAt: Date
}

struct CircleFeedResponse: Codable {
    let items: [CirclePost]
}

struct CircleTransferTicket: Codable {
    let downloadUrl: URL
    let expiresInSeconds: Int
}
