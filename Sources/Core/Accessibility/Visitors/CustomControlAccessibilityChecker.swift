import Foundation
import SwiftSyntax

/// Checks accessibility issues specific to custom controls in SwiftUI.
/// This checker analyzes custom view types that should have accessibility traits.
class CustomControlAccessibilityChecker: VariableDeclAccessibilityCheckerProtocol {

    let visitor: AccessibilityVisitor

    init(visitor: AccessibilityVisitor) {
        self.visitor = visitor
    }

    func checkAccessibility(_ node: VariableDeclSyntax) {
        // Intentionally unimplemented — reserved for future custom-control accessibility checks.
    }
}
