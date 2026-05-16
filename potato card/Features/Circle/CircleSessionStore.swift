import Foundation
import SwiftUI

@MainActor
final class CircleSessionStore: ObservableObject {
    @Published private(set) var profile: CircleUserProfile?

    private enum Keys {
        static let accessToken = "circleAccessToken"
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

    var isRegistered: Bool {
        token != nil && profile != nil
    }

    func loadFromStorage() {
        let userID = defaults.string(forKey: Keys.userID) ?? ""
        let username = defaults.string(forKey: Keys.username) ?? ""
        let avatarKey = defaults.string(forKey: Keys.avatarKey) ?? ""
        guard !userID.isEmpty, !username.isEmpty, !avatarKey.isEmpty else { return }
        profile = CircleUserProfile(id: userID, username: username, avatarKey: avatarKey)
    }

    func saveSession(token: String, profile: CircleUserProfile) {
        defaults.set(token, forKey: Keys.accessToken)
        defaults.set(profile.id, forKey: Keys.userID)
        defaults.set(profile.username, forKey: Keys.username)
        defaults.set(profile.avatarKey, forKey: Keys.avatarKey)
        self.profile = profile
    }

    func signOut() {
        defaults.removeObject(forKey: Keys.accessToken)
        defaults.removeObject(forKey: Keys.userID)
        defaults.removeObject(forKey: Keys.username)
        defaults.removeObject(forKey: Keys.avatarKey)
        profile = nil
    }
}
