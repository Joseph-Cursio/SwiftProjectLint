import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Enforces architectural layer boundaries in single-target Swift apps.
///
/// For multi-target or modular projects the Swift compiler enforces boundaries at
/// build time via separate SPM targets — this rule adds no value there.
///
/// In a single-target app, layer separation is only a folder convention. This visitor
/// checks each file against the `architectural_layers` config and flags:
///
/// - **Import violations** — `import` statements for frameworks forbidden in that layer
///   (e.g. `CoreData` in a `Domain/` file), or, when the layer sets `allowed_imports`, for any
///   framework not on that list.
/// - **Type violations** — references to specific type names forbidden in that layer
///   (e.g. `URLSession` in `Domain/` — Foundation is widely imported so the import
///   check alone won't catch this).
///
/// The rule is a no-op when `layerPolicies` is empty (the default). Activate it by
/// adding an `architectural_layers:` block to `.swiftprojectlint.yml`.
final class ArchitecturalBoundaryVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""
    private var currentPolicy: LayerPolicy?

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        currentFilePath = filePath
        currentPolicy = LayerPolicy.layer(for: filePath, in: layerPolicies)
    }

    // MARK: - Import-based check

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let policy = currentPolicy else { return .visitChildren }
        let moduleName = node.path.map(\.name.text).joined(separator: ".")

        if policy.forbiddenImports.contains(moduleName) {
            addIssue(
                severity: .warning,
                message: "'\(moduleName)' must not be imported in the '\(policy.name)' layer",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Move '\(moduleName)' usage to an appropriate layer "
                    + "and expose it through a protocol or service.",
                ruleName: .architecturalBoundary
            )
        } else if policy.allowsImport(of: moduleName) == false {
            // One finding per import: a module both forbidden and unlisted is reported as forbidden.
            addIssue(
                severity: .warning,
                message: "'\(moduleName)' is not an allowed import in the '\(policy.name)' layer",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Move this code to a layer that may use '\(moduleName)', or add it to the "
                    + "'\(policy.name)' layer's allowed_imports if the dependency is intended.",
                ruleName: .architecturalBoundary
            )
        }
        return .visitChildren
    }

    // MARK: - Type-based check

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        checkTypeName(node.name.text, syntax: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        checkTypeName(node.baseName.text, syntax: Syntax(node))
        return .visitChildren
    }

    // MARK: - Private

    private func checkTypeName(_ name: String, syntax: Syntax) {
        guard let policy = currentPolicy,
              policy.forbiddenTypes.contains(name) else { return }

        addIssue(
            severity: .warning,
            message: "'\(name)' must not be used in the '\(policy.name)' layer",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: syntax),
            suggestion: "Introduce an abstraction (protocol or service) that hides "
                + "'\(name)' behind a layer-appropriate interface.",
            ruleName: .architecturalBoundary
        )
    }
}
