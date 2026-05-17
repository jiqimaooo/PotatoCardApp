import Combine
import Foundation
import SwiftUI

@MainActor
final class CircleSessionStore: ObservableObject {
    static let didSignOutNotification = Notification.Name("CircleSessionStoreDidSignOut")

    @Published private(set) var profile: CircleUserProfile?

    private enum Keys {
        static let accessToken = "circleAccessToken"
        static let refreshToken = "circleRefreshToken"
        static let userID = "circleUserID"
        static let username = "circleUsername"
        static let avatarKey = "circleAvatarKey"
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
        guard !userID.isEmpty, !username.isEmpty, !avatarKey.isEmpty, token != nil, refreshToken != nil else {
            profile = nil
            return
        }
        profile = CircleUserProfile(id: userID, username: username, avatarKey: avatarKey)
    }

    func saveSession(accessToken: String, refreshToken: String, profile: CircleUserProfile) {
        defaults.set(accessToken, forKey: Keys.accessToken)
        defaults.set(refreshToken, forKey: Keys.refreshToken)
        defaults.set(profile.id, forKey: Keys.userID)
        defaults.set(profile.username, forKey: Keys.username)
        defaults.set(profile.avatarKey, forKey: Keys.avatarKey)
        self.profile = profile
    }

    func saveSession(_ session: CircleAuthSession) {
        saveSession(accessToken: session.accessToken, refreshToken: session.refreshToken, profile: session.profile)
    }

    func signOut() {
        defaults.removeObject(forKey: Keys.accessToken)
        defaults.removeObject(forKey: Keys.refreshToken)
        defaults.removeObject(forKey: Keys.userID)
        defaults.removeObject(forKey: Keys.username)
        defaults.removeObject(forKey: Keys.avatarKey)
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
}
