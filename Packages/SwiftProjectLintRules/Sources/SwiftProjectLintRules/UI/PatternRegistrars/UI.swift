import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// Registers patterns related to UI best practices in SwiftUI.
/// This registrar handles patterns for navigation, ForEach usage, styling, and error handling.

class UIPatterns: BasePatternRegistrar {
    override func registerPatterns() {
        let patterns = [
            SyntaxPattern(
                name: .nestedNavigationView,
                visitor: UIVisitor.self,
                severity: .warning,
                category: .uiPatterns,
                messageTemplate: "Nested NavigationView detected, this can cause issues",
                suggestion: "Use NavigationStack or NavigationSplitView instead",
                description: "Detects nested NavigationView usage which can cause navigation issues"
            ),
            SyntaxPattern(
                name: .missingPreview,
                visitor: UIVisitor.self,
                severity: .info,
                category: .uiPatterns,
                messageTemplate: "Consider adding a preview for {viewName}",
                suggestion: "Add a PreviewProvider to help with development and testing",
                description: "Detects SwiftUI views missing preview providers"
            ),
            SyntaxPattern(
                name: .forEachWithoutID,
                visitor: UIVisitor.self,
                severity: .warning,
                category: .uiPatterns,
                messageTemplate: "ForEach should specify an explicit ID for better performance",
                suggestion: "Add an explicit id parameter to ForEach",
                description: "Detects ForEach usage without explicit ID specification"
            ),
            SyntaxPattern(
                name: .forEachWithSelfID,
                visitor: ForEachSelfIDVisitor.self,
                severity: .warning,
                category: .uiPatterns,
                messageTemplate: "Using .self as id in ForEach can cause performance issues",
                suggestion: "Use a unique identifier property instead of .self for better performance",
                description: "Detects usage of .self or .self as the id parameter in ForEach"
            ),
            SyntaxPattern(
                name: .inconsistentStyling,
                visitor: UIVisitor.self,
                severity: .info,
                category: .uiPatterns,
                messageTemplate: "Inconsistent styling detected in {context}",
                suggestion: "Use consistent styling patterns and consider creating reusable style components",
                description: "Detects inconsistent styling patterns across the UI"
            ),
            SyntaxPattern(
                name: .forEachWithoutIDUI,
                visitor: UIVisitor.self,
                severity: .warning,
                category: .uiPatterns,
                messageTemplate: "ForEach should specify an explicit ID for better performance",
                suggestion: "Add an explicit id parameter to ForEach",
                description: "Detects ForEach usage without explicit ID specification in UI contexts"
            ),
            SyntaxPattern(
                name: .basicErrorHandling,
                visitor: UIVisitor.self,
                severity: .info,
                category: .uiPatterns,
                messageTemplate: "Consider adding error handling for {operation}",
                suggestion: "Add proper error handling and user feedback for better UX",
                description: "Detects operations that could benefit from error handling"
            )
        ]
        registry.register(patterns: patterns)
    }
}
