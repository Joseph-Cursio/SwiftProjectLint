import Foundation

/// A `UserDefaults` store of one test's own, removed when the test lets go of it.
///
/// `UserDefaults.standard` is the test process's domain, which every test process on the machine shares. A mutation
/// tester runs several at once, so a test that wrote a fixed key there read another process's value, and was killed,
/// or not, by whichever wrote last. A fixed suite name would be shared the same way, so each store's name is a UUID.
final class IsolatedDefaults: @unchecked Sendable { // `UserDefaults` is thread-safe
    let suiteName = "SwiftProjectLintTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        // Only a name `UserDefaults` reserves, such as the app's own domain, gives nil.
        guard let store = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("UserDefaults refused the suite name \(suiteName)")
        }
        defaults = store
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
