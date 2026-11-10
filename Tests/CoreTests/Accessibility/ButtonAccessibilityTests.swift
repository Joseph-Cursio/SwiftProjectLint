@testable import Core
@testable import SwiftProjectLintRules
import Testing

@Suite
struct ButtonAccessibilityTests {

    // MARK: - Test Helper Methods

    func makeAccessibilityVisitor() -> AccessibilityVisitor {
        // Initialize shared registry if not already done
        TestRegistryManager.initializeSharedRegistry()
        return AccessibilityVisitor(patternCategory: .accessibility)
    }
}
