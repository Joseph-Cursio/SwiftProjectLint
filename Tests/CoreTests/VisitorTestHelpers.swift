import Foundation
import SwiftParser
@testable import Core

// MARK: - Accessibility

/// Creates a ready-to-use AccessibilityVisitor with the shared registry initialized.
func makeAccessibilityVisitor() -> AccessibilityVisitor {
    TestRegistryManager.initializeSharedRegistry()
    return AccessibilityVisitor(patternCategory: .accessibility)
}

// MARK: - State Variable

/// Parses `source`, walks a StateVariableVisitor over it, and returns the visitor.
///
/// Uses a fixed view name and file path suitable for unit tests.
func makeStateVariableVisitor(for source: String) -> StateVariableVisitor {
    let syntax = Parser.parse(source: source)
    let visitor = StateVariableVisitor(
        viewName: "TestView",
        filePath: "/test/TestView.swift",
        sourceContents: source
    )
    visitor.walk(syntax)
    return visitor
}
