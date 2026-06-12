import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that flags `@preconcurrency import SomeModule`.
///
/// `@preconcurrency` on an import softens (or silences) concurrency diagnostics for
/// every type vended by that module — `Sendable` checking is relaxed, isolation
/// mismatches are downgraded. That is a legitimate, even recommended, way to consume a
/// library that predates Swift Concurrency, but it is also a blanket escape hatch: once
/// applied, a genuine concurrency problem involving that module's types compiles
/// silently. Surfacing each one keeps the suppression visible and reviewable, and
/// invites removing it once the dependency annotates its own concurrency.
///
/// This is the import-level counterpart to
/// [Preconcurrency Conformance](preconcurrency-conformance.md), which deliberately
/// covers only `@preconcurrency` on conformances and skips imports.
///
/// **Severity is `info`** — the annotation is frequently the correct tool, so this is
/// an audit signal, not a defect.
final class PreconcurrencyImportVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        guard hasPreconcurrencyAttribute(node.attributes) else { return .visitChildren }

        let moduleName = node.path.trimmedDescription
        addIssue(
            severity: .info,
            message: "@preconcurrency import '\(moduleName)' relaxes concurrency checking "
                + "for every type from that module",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Keep the suppression only while '\(moduleName)' lacks its own "
                + "concurrency annotations; remove @preconcurrency once it adopts Sendable / "
                + "isolation, or scope the relaxation to specific types instead of the whole import.",
            ruleName: .preconcurrencyImport
        )
        return .visitChildren
    }

    private func hasPreconcurrencyAttribute(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "preconcurrency"
        }
    }
}
