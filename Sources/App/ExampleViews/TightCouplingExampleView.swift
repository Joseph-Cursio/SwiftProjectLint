import SwiftUI

// MARK: - Supporting types (all private to this file)

// Tight Coupling Rule: Singleton Usage — DataManager.shared creates hard coupling
private class DataManager {
    static let shared = DataManager()
    func fetch() {}
}

private class AnalysisCoordinator {
    func run() {
        // Tight Coupling Rule: Singleton Usage — should inject DataManager instead
        DataManager.shared.fetch()
    }
}

// Tight Coupling Rule: Law of Demeter — three-level property chain
private class Address {
    var street: String = ""
}

private class Profile {
    var address = Address()
}

private class UserAccount {
    var profile = Profile()
}

private class ProfileDisplay {
    let user = UserAccount()

    func showStreet() -> String {
        // Tight Coupling Rule: Law of Demeter — user.profile.address is a train wreck
        return user.profile.address.street
    }
}

// Tight Coupling Rule: Direct Instantiation — should be injected
private class ReportingService {
    func report(_ msg: String) {}
}

private class Dashboard {
    // Tight Coupling Rule: Direct Instantiation
    private let reporter = ReportingService()
}

// Tight Coupling Rule: Concrete Type Usage — parameter should use a protocol
private class InventoryRepository {
    func items() -> [String] { [] }
}

private class StockView {
    // Tight Coupling Rule: Concrete Type Usage — InventoryRepository should be a protocol
    func display(repo: InventoryRepository) {}
}

// Tight Coupling Rule: Accessing Implementation Details — underscore prefix
private class CacheService {
    var internalCache: [String: Any] = [:]
}

private class CacheReader {
    private let cache = CacheService()

    func read(key: String) -> Any? {
        // Tight Coupling Rule: Accessing Implementation Details
        return cache.internalCache[key]
    }
}

// MARK: - View

/// Demonstrates all five tight coupling lint rules so that scanning this project
/// with `--categories architecture` will produce at least one violation per rule.
struct TightCouplingExampleView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Tight Coupling Examples")
                .font(.headline)

            Text("This view intentionally contains code that violates tight coupling rules.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text(
                "Rules demonstrated: Singleton Usage, Law of Demeter, "
                + "Direct Instantiation, Concrete Type Usage, "
                + "Accessing Implementation Details"
            )
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

#Preview {
    TightCouplingExampleView()
}
