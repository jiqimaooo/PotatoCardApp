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
