import Foundation

struct CircleUserProfile: Codable, Equatable, Identifiable {
    let id: String
    let username: String
    let avatarKey: String
    let avatarUrl: URL?

    init(id: String, username: String, avatarKey: String, avatarUrl: URL? = nil) {
        self.id = id
        self.username = username
        self.avatarKey = avatarKey
        self.avatarUrl = avatarUrl
    }
}

enum CirclePostChannel: String, Codable, Equatable {
    case community = "COMMUNITY"
    case driftBottle = "DRIFT_BOTTLE"
}

struct CirclePost: Codable, Equatable, Identifiable {
    struct Author: Codable, Equatable {
        let id: String
        let username: String
        let avatarKey: String
        let avatarUrl: URL?
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
    let previewUrl: URL?
    let previewWidth: Int?
    let previewHeight: Int?
    let channel: CirclePostChannel
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case author
        case tags
        case lockedPreviewStyle
        case targetWidth
        case targetHeight
        case colorMode
        case transferCount
        case previewUrl
        case previewWidth
        case previewHeight
        case channel
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decode(Author.self, forKey: .author)
        tags = try container.decode([String].self, forKey: .tags)
        lockedPreviewStyle = try container.decode(String.self, forKey: .lockedPreviewStyle)
        targetWidth = try container.decodeIfPresent(Int.self, forKey: .targetWidth)
        targetHeight = try container.decodeIfPresent(Int.self, forKey: .targetHeight)
        colorMode = try container.decodeIfPresent(String.self, forKey: .colorMode)
        transferCount = try container.decode(Int.self, forKey: .transferCount)
        previewUrl = try container.decodeIfPresent(URL.self, forKey: .previewUrl)
        previewWidth = try container.decodeIfPresent(Int.self, forKey: .previewWidth)
        previewHeight = try container.decodeIfPresent(Int.self, forKey: .previewHeight)
        channel = try container.decodeIfPresent(CirclePostChannel.self, forKey: .channel) ?? .community
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

struct CircleFeedResponse: Codable {
    let items: [CirclePost]
    let nextCursor: String?
    let hasMore: Bool
}

struct CircleDriftBottleDrawResponse: Codable {
    let item: CirclePost?
    let dailyLimit: Int
    let remainingDraws: Int
    let resetAt: Date
    let reason: String?
}

struct CircleTransferTicket: Codable {
    let downloadUrl: URL
    let expiresInSeconds: Int
}

enum CircleImageTokenStatus: String, Codable, Equatable {
    case active = "ACTIVE"
    case claimed = "CLAIMED"
    case expired = "EXPIRED"
    case transferred = "TRANSFERRED"
    case destroyed = "DESTROYED"
}

struct CircleImageToken: Codable, Equatable, Identifiable {
    let id: String
    let tokenCode: String
    let senderUserId: String
    let receiverUserId: String?
    let isBurnAfterRead: Bool
    let status: CircleImageTokenStatus
    let claimedAt: Date?
    let transferredAt: Date?
    let destroyedAt: Date?
    let expiresAt: Date?
    let createdAt: Date?
}

struct CircleImageTokenListResponse: Codable {
    let items: [CircleImageToken]
}

struct CircleAuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let profile: CircleUserProfile
}

struct CirclePasskeyRegistrationOptions: Codable {
    struct RelyingParty: Codable {
        let id: String
        let name: String
    }

    struct User: Codable {
        let id: String
        let name: String
        let displayName: String
    }

    let challenge: String
    let rp: RelyingParty
    let user: User
}

struct CirclePasskeyRegistrationResponse: Codable {
    struct Response: Codable {
        let clientDataJSON: String
        let attestationObject: String
        let transports: [String]
    }

    let id: String
    let rawId: String
    let type: String
    let response: Response
    let clientExtensionResults: [String: String]
}
