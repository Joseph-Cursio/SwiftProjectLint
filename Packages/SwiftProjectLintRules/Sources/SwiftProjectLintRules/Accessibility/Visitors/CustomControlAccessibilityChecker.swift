import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Checks accessibility issues specific to custom controls in SwiftUI.
/// This checker analyzes custom view types that should have accessibility traits.
class CustomControlAccessibilityChecker {

    let visitor: AccessibilityVisitor

    init(visitor: AccessibilityVisitor) {
        self.visitor = visitor
    }

    func checkAccessibility(_ _: VariableDeclSyntax) {
        // Intentionally unimplemented — reserved for future custom-control accessibility checks.
    }
}
