import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that flags `@preconcurrency` on conformances of locally
/// defined types.
///
/// `@preconcurrency` has two valid forms:
/// - `@preconcurrency import SomeModule` — softens concurrency errors from a
///   third-party library that predates Swift Concurrency. **Not flagged.**
/// - `@preconcurrency extension MyType: SomeProtocol` — applied to a conformance
///   to silence isolation errors. **Flagged when the extended type is defined in
///   the same project.**
///
/// When `@preconcurrency` appears on a conformance of your own type, it grandfathers
/// in isolation errors that indicate a real design problem. The fix is to add proper
/// concurrency annotations (`@MainActor`, `Sendable`, actor isolation), not to
/// suppress the errors at the conformance site.
///
/// **Detection:** The extended type name is checked against `knownLocalTypeNames`,
/// the pre-scanned set of all class/struct/enum/actor declarations in the project.
/// This correctly handles single-target monoliths where all project types are local.
/// False positives can occur if a local type name coincidentally matches a
/// third-party type name — treat those as false-positive suppression candidates.
final class PreconcurrencyConformanceVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard hasPreconcurrency(node.attributes) else { return .visitChildren }
        guard node.inheritanceClause != nil else {
            // @preconcurrency on an extension without a conformance — not the pattern we flag
            return .visitChildren
        }

        let extendedTypeName = baseTypeName(from: node.extendedType.trimmedDescription)

        // Only flag when the extended type is known to be defined in this project
        guard knownLocalTypeNames.contains(extendedTypeName) else { return .visitChildren }

        addIssue(
            severity: .warning,
            message: "@preconcurrency on conformance of '\(extendedTypeName)' suppresses "
                + "isolation errors that belong to your code",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Add proper concurrency annotations (@MainActor, Sendable, actor isolation) "
                + "to '\(extendedTypeName)' instead of using @preconcurrency.",
            ruleName: .preconcurrencyConformance
        )

        return .visitChildren
    }

    // MARK: - Private

    private func hasPreconcurrency(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            guard let attr = element.as(AttributeSyntax.self) else { return false }
            return attr.attributeName.trimmedDescription == "preconcurrency"
        }
    }

    /// Strips generic arguments and optional-chaining from a type name.
    /// `"MyView<Foo>"` → `"MyView"`, `"Optional<Bar>"` → `"Optional"`.
    private func baseTypeName(from typeName: String) -> String {
        let stripped = typeName.components(separatedBy: "<").first ?? typeName
        return stripped.trimmingCharacters(in: .whitespaces)
    }
}
