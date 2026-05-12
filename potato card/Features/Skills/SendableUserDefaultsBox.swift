import Foundation

struct SendableUserDefaultsBox: @unchecked Sendable {
    let userDefaults: UserDefaults

    init(_ userDefaults: UserDefaults) {
        // UserDefaults 自身可跨线程使用，这里只用于通过 @Sendable 闭包检查。
        self.userDefaults = userDefaults
    }
}
