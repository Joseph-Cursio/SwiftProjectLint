import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// A SwiftSyntax visitor that detects two heuristics for encapsulation violations:
/// 1. Accessing underscore-prefixed members on non-self/super objects.
/// 2. Accessing members via a force-cast base to a service-like concrete type.
class AccessingImplementationDetailsVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    private enum ServiceSuffix: String, CaseIterable {
        case manager = "Manager"
        case service = "Service"
        case store = "Store"
        case provider = "Provider"
        case client = "Client"
        case repository = "Repository"
        case handler = "Handler"
        case controller = "Controller"
        case factory = "Factory"
        case adapter = "Adapter"
        case viewModel = "ViewModel"
        case coordinator = "Coordinator"
    }

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        self.currentFilePath = filePath
    }

    // MARK: - MemberAccessExprSyntax

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        guard let base = node.base else { return .visitChildren }

        let memberName = node.declName.baseName.text

        // Heuristic A: underscore-prefix member on a non-self/super base
        if memberName.hasPrefix("_") {
            // Skip test files — test code commonly accesses internals
            if isTestOrFixtureFile() {
                return .visitChildren
            }
            // Skip self._member
            if let ref = base.as(DeclReferenceExprSyntax.self),
               ref.baseName.text == "self" {
                return .visitChildren
            }
            // Skip super._member
            if base.is(SuperExprSyntax.self) {
                return .visitChildren
            }
            let baseDesc = base.as(DeclReferenceExprSyntax.self)?.baseName.text ?? "object"
            addIssue(
                severity: .warning,
                message: "Accessing implementation detail '\(memberName)' on '\(baseDesc)' " +
                    "— prefer the public interface",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Expose '\(memberName)' through a protocol or public API",
                ruleName: .accessingImplementationDetails
            )
            return .visitChildren
        }

        // Heuristic B: force-cast base to service-like concrete type
        if let castTypeName = extractForceCastTypeName(from: base) {
            addIssue(
                severity: .warning,
                message: "Accessing '\(memberName)' via force-cast to concrete type '\(castTypeName)' " +
                    "— prefer the protocol interface",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Avoid force-casting '\(castTypeName)'; add '\(memberName)' to the protocol instead",
                ruleName: .accessingImplementationDetails
            )
        }
        return .visitChildren
    }

    // MARK: - Helpers

    /// Searches the base expression's text for an `as!` cast to a service-like type.
    /// Uses textual inspection because sub-walking non-root nodes crashes in SwiftSyntax 601.
    private func extractForceCastTypeName(from expr: ExprSyntax) -> String? {
        let text = expr.trimmedDescription
        // Find "as! TypeName" — extract the identifier that follows
        guard let castRange = text.range(of: "as! ") else { return nil }
        let afterCast = text[castRange.upperBound...]
        let typeName = String(afterCast.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" }))
        return qualifyingServiceName(typeName)
    }

    /// Returns the name if it starts uppercase and ends with a service-like suffix, else nil.
    private func qualifyingServiceName(_ name: String) -> String? {
        guard name.first?.isUppercase == true,
              ServiceSuffix.allCases.contains(where: { name.hasSuffix($0.rawValue) })
        else { return nil }
        return name
    }
}
