import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `@ObservedObject` with inline initialization.
///
/// `@ObservedObject` does not own the object it observes, so creating one inline
/// (e.g. `@ObservedObject var viewModel = ViewModel()`) causes the object to be
/// recreated on every view re-render. Use `@StateObject` instead for owned objects.
final class ObservedObjectInlineVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .observedObjectInline else { return .visitChildren }

        // Check for @ObservedObject attribute
        let hasObservedObject = node.attributes.contains { attr in
            guard let attribute = attr.as(AttributeSyntax.self),
                  let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self) else { return false }
            return identifier.name.text == "ObservedObject"
        }
        guard hasObservedObject else { return .visitChildren }

        // Check if any binding has an initializer
        for binding in node.bindings where binding.initializer != nil {
            addIssue(
                severity: .warning,
                message: "@ObservedObject with inline initialization — "
                    + "the object is recreated on every view re-render",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Use @StateObject instead when the view creates the object. "
                    + "@ObservedObject is for objects passed in from a parent view.",
                ruleName: .observedObjectInline
            )
        }
        return .visitChildren
    }
}
