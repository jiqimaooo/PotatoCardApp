import Combine
import Foundation
import SwiftUI

@MainActor
final class CircleSessionStore: ObservableObject {
    static let didSignOutNotification = Notification.Name("CircleSessionStoreDidSignOut")
    private static var refreshTask: Task<CircleAuthSession, Error>?

    @Published private(set) var profile: CircleUserProfile?

    private enum Keys {
        static let accessToken = "circleAccessToken"
        static let refreshToken = "circleRefreshToken"
        static let userID = "circleUserID"
        static let username = "circleUsername"
        static let avatarKey = "circleAvatarKey"
        static let avatarURL = "circleAvatarURL"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var token: String? {
        let token = defaults.string(forKey: Keys.accessToken) ?? ""
        return token.isEmpty ? nil : token
    }

    var refreshToken: String? {
        let token = defaults.string(forKey: Keys.refreshToken) ?? ""
        return token.isEmpty ? nil : token
    }

    var isRegistered: Bool {
        token != nil && refreshToken != nil && profile != nil
    }

    var shouldRefreshAccessToken: Bool {
        guard let token else { return false }
        guard let expiry = accessTokenExpiryDate(token) else { return true }
        return expiry.timeIntervalSinceNow < 60
    }

    func loadFromStorage() {
        let userID = defaults.string(forKey: Keys.userID) ?? ""
        let username = defaults.string(forKey: Keys.username) ?? ""
        let avatarKey = defaults.string(forKey: Keys.avatarKey) ?? ""
        let avatarURLString = defaults.string(forKey: Keys.avatarURL) ?? ""
        guard !userID.isEmpty, !username.isEmpty, !avatarKey.isEmpty, token != nil, refreshToken != nil else {
            profile = nil
            return
        }
        profile = CircleUserProfile(
            id: userID,
            username: username,
            avatarKey: avatarKey,
            avatarUrl: URL(string: avatarURLString)
        )
    }

    func saveSession(accessToken: String, refreshToken: String, profile: CircleUserProfile) {
        defaults.set(accessToken, forKey: Keys.accessToken)
        defaults.set(refreshToken, forKey: Keys.refreshToken)
        defaults.set(profile.id, forKey: Keys.userID)
        defaults.set(profile.username, forKey: Keys.username)
        defaults.set(profile.avatarKey, forKey: Keys.avatarKey)
        if let avatarUrl = profile.avatarUrl {
            defaults.set(avatarUrl.absoluteString, forKey: Keys.avatarURL)
        } else {
            defaults.removeObject(forKey: Keys.avatarURL)
        }
        self.profile = profile
    }

    func saveSession(_ session: CircleAuthSession) {
        saveSession(accessToken: session.accessToken, refreshToken: session.refreshToken, profile: session.profile)
    }

    func updateProfileAvatarURL(_ avatarUrl: URL) {
        guard let profile else { return }
        let updatedProfile = CircleUserProfile(
            id: profile.id,
            username: profile.username,
            avatarKey: profile.avatarKey,
            avatarUrl: avatarUrl
        )
        defaults.set(avatarUrl.absoluteString, forKey: Keys.avatarURL)
        self.profile = updatedProfile
    }

    func updateProfile(_ profile: CircleUserProfile) {
        defaults.set(profile.id, forKey: Keys.userID)
        defaults.set(profile.username, forKey: Keys.username)
        defaults.set(profile.avatarKey, forKey: Keys.avatarKey)
        if let avatarUrl = profile.avatarUrl {
            defaults.set(avatarUrl.absoluteString, forKey: Keys.avatarURL)
        } else {
            defaults.removeObject(forKey: Keys.avatarURL)
        }
        self.profile = profile
    }

    func validAccessToken(using apiClient: CircleAPIClient, forceRefresh: Bool = false) async throws -> String {
        guard let refreshToken else {
            throw CircleAPIError.missingAuthToken
        }

        if forceRefresh || shouldRefreshAccessToken {
            let session = try await Self.refreshSession(refreshToken: refreshToken, using: apiClient)
            saveSession(session)
        }

        guard let accessToken = token else {
            throw CircleAPIError.missingAuthToken
        }
        return accessToken
    }

    func signOut() {
        defaults.removeObject(forKey: Keys.accessToken)
        defaults.removeObject(forKey: Keys.refreshToken)
        defaults.removeObject(forKey: Keys.userID)
        defaults.removeObject(forKey: Keys.username)
        defaults.removeObject(forKey: Keys.avatarKey)
        defaults.removeObject(forKey: Keys.avatarURL)
        profile = nil
        NotificationCenter.default.post(name: Self.didSignOutNotification, object: nil)
    }

    private func accessTokenExpiryDate(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = payload.count % 4
        if padding > 0 {
            payload += String(repeating: "=", count: 4 - padding)
        }

        guard
            let data = Data(base64Encoded: payload),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let expiry = json["exp"] as? TimeInterval
        else {
            return nil
        }
        return Date(timeIntervalSince1970: expiry)
    }

    private static func refreshSession(refreshToken: String, using apiClient: CircleAPIClient) async throws -> CircleAuthSession {
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task {
            try await apiClient.refreshSession(refreshToken: refreshToken)
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
}
