import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registers patterns related to performance optimization in SwiftUI.
/// This registrar handles patterns for view body optimization, ForEach usage, and performance anti-patterns.

class Performance: BasePatternRegistrar {
    override func registerPatterns() {
        let patterns = [
            SyntaxPattern(
                name: .expensiveOperationInViewBody,
                visitor: PerformanceVisitor.self,
                severity: .warning,
                category: .performance,
                messageTemplate: "Expensive operation detected in view body: {operation}",
                suggestion: "Move expensive operations outside the view body or use lazy loading",
                description: "Detects expensive operations that should not be performed in view bodies"
            ),
            SyntaxPattern(
                name: .forEachWithoutID,
                visitor: PerformanceVisitor.self,
                severity: .warning,
                category: .performance,
                messageTemplate: "ForEach should specify an explicit ID for better performance",
                suggestion: "Add an explicit id parameter to ForEach",
                description: "Detects ForEach usage without explicit ID specification"
            ),
            SyntaxPattern(
                name: .largeViewBody,
                visitor: PerformanceVisitor.self,
                severity: .warning,
                category: .performance,
                messageTemplate: "View body is too large ({lineCount} lines), consider breaking it down",
                suggestion: "Extract complex view logic into separate view components",
                description: "Detects view bodies that exceed recommended size limits"
            ),
            SyntaxPattern(
                name: .largeViewHelper,
                visitor: PerformanceVisitor.self,
                severity: .warning,
                category: .performance,
                messageTemplate: "View helper exceeds 50 lines, consider extracting into a child view",
                suggestion: "Extract large helper computed properties or methods into dedicated child views",
                description: "Detects helper properties or methods in View structs that are too long"
            ),
            SyntaxPattern(
                name: .forEachSelfID,
                visitor: ForEachSelfIDVisitor.self,
                severity: .warning,
                category: .performance,
                messageTemplate: "ForEach using unsafe ID keypath (.self or .hashValue)"
                    + " can cause performance issues or incorrect view updates",
                suggestion: "Use a stable, unique identifier like \\.id."
                    + " Conform the element to Identifiable if possible",
                description: "Detects .self or .hashValue as the id parameter in ForEach"
            ),
            SyntaxPattern(
                name: .volatileViewID,
                visitor: VolatileViewIDVisitor.self,
                severity: .warning,
                category: .performance,
                messageTemplate: "View identity is reset via `.id({token})`, but '{token}' is "
                    + "reassigned elsewhere — changing a view's id forces a full subtree rebuild",
                suggestion: "Remove the changing `.id(...)` and drive updates through the state "
                    + "the subviews already observe; churning a List/Table identity can cause "
                    + "reentrant NSTableView updates and lost scroll/selection state",
                description: "Detects `.id(token)` on a view where the token is reassigned, "
                    + "forcing SwiftUI to discard and rebuild the subtree"
            ),
            SyntaxPattern(
                name: .unnecessaryViewUpdate,
                visitor: PerformanceVisitor.self,
                severity: .info,
                category: .performance,
                messageTemplate: "Unnecessary view update detected for '{variableName}'",
                suggestion: "Consider using @State only when UI changes are needed",
                description: "Detects state variables that trigger unnecessary view updates"
            )
        ]
        registry.register(patterns: patterns)
        registry.register(registrars: [
            ViewBuilderComplexity(),
            CustomModifierPerformance(),
            FormatterInViewBody(),
            AnyViewUsage(),
            GeometryReaderOveruse(),
            UnboundedTaskGroup(),
            OnReceiveWithoutDebounce()
        ])
    }
}
