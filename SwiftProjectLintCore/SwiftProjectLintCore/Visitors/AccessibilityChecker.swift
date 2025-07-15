import Foundation
import SwiftSyntax

/// Protocol defining the interface for accessibility checkers.
/// Each checker is responsible for analyzing a specific type of SwiftUI element
/// for accessibility-related issues.
protocol AccessibilityCheckerProtocol {
    /// The visitor that owns this checker.
    var visitor: AccessibilityVisitor { get }
    
    /// Checks the accessibility of a specific element.
    /// - Parameter node: The syntax node to check.
    func checkAccessibility(_ node: FunctionCallExprSyntax)
}

/// Protocol for checkers that can analyze member access expressions.
protocol MemberAccessAccessibilityCheckerProtocol {
    /// The visitor that owns this checker.
    var visitor: AccessibilityVisitor { get }
    
    /// Checks the accessibility of a member access expression.
    /// - Parameter node: The member access expression to check.
    func checkAccessibility(_ node: MemberAccessExprSyntax)
}

/// Protocol for checkers that can analyze variable declarations.
protocol VariableDeclAccessibilityCheckerProtocol {
    /// The visitor that owns this checker.
    var visitor: AccessibilityVisitor { get }
    
    /// Checks the accessibility of a variable declaration.
    /// - Parameter node: The variable declaration to check.
    func checkAccessibility(_ node: VariableDeclSyntax)
} 