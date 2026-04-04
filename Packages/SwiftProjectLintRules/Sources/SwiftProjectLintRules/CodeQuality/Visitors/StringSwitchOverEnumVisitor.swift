import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `switch someEnum.rawValue { case "..." }` patterns where the
/// developer loses exhaustiveness checking by switching on the raw `String`
/// instead of the enum value itself.
///
/// Also flags `switch String(describing: someEnum)` as a related anti-pattern.
///
/// **Suppression:** The warning is suppressed when the switch appears inside a
/// `Codable` implementation (`init(from decoder:)` or `encode(to encoder:)`),
/// where switching on raw strings from external input is the expected pattern.
final class StringSwitchOverEnumVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Visit

    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .stringSwitchOverEnum else { return .visitChildren }

        if isRawValueSwitch(node) || isStringDescribingSwitch(node) {
            guard isInsideCodableMethod(node) == false else { return .visitChildren }
            addIssue(node: Syntax(node))
        }

        return .visitChildren
    }

    // MARK: - Detection: .rawValue

    /// Returns `true` when the switch subject is `<expr>.rawValue` and at least
    /// one case arm uses a string literal pattern.
    private func isRawValueSwitch(_ node: SwitchExprSyntax) -> Bool {
        guard let memberAccess = node.subject.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "rawValue",
              let base = memberAccess.base else {
            return false
        }

        guard hasStringLiteralCase(node) else { return false }

        return isLikelyEnumBase(base)
    }

    // MARK: - Detection: String(describing:)

    /// Returns `true` when the switch subject is `String(describing: <expr>)`.
    private func isStringDescribingSwitch(_ node: SwitchExprSyntax) -> Bool {
        guard let call = node.subject.as(FunctionCallExprSyntax.self),
              let callee = call.calledExpression.as(DeclReferenceExprSyntax.self),
              callee.baseName.text == "String" else {
            return false
        }

        let hasDescribingLabel = call.arguments.contains { argument in
            argument.label?.text == "describing"
        }

        return hasDescribingLabel && hasStringLiteralCase(node)
    }

    // MARK: - Helpers

    /// Returns `true` when at least one case arm in the switch uses a string
    /// literal pattern (e.g. `case "active":`).
    private func hasStringLiteralCase(_ node: SwitchExprSyntax) -> Bool {
        node.cases.contains { switchCase in
            guard let caseItem = switchCase.as(SwitchCaseSyntax.self),
                  let caseLabel = caseItem.label.as(SwitchCaseLabelSyntax.self) else {
                return false
            }
            return caseLabel.caseItems.contains { item in
                item.pattern.as(ExpressionPatternSyntax.self)?
                    .expression.as(StringLiteralExprSyntax.self) != nil
            }
        }
    }

    /// Heuristically determines whether the base expression of `.rawValue` is
    /// likely an enum. Uses `knownEnumTypes` when populated by cross-file
    /// analysis; otherwise falls back to structural heuristics.
    private func isLikelyEnumBase(_ base: ExprSyntax) -> Bool {
        let baseName = extractBaseName(base)

        // If cross-file analysis populated knownEnumTypes, check it
        if knownEnumTypes.isEmpty == false, let baseName {
            if knownEnumTypes.contains(baseName) {
                return true
            }
        }

        // Heuristic: any `.rawValue` access with string literal cases is
        // suspicious enough to flag (this is an opt-in rule)
        return true
    }

    /// Extracts the type or variable name from an expression for lookup against
    /// `knownEnumTypes`. Handles simple identifiers and member access chains.
    private func extractBaseName(_ expr: ExprSyntax) -> String? {
        if let declRef = expr.as(DeclReferenceExprSyntax.self) {
            return declRef.baseName.text
        }
        if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
            return memberAccess.declName.baseName.text
        }
        return nil
    }

    /// Returns `true` when the switch is inside a `Codable` method
    /// (`init(from decoder: Decoder)` or `encode(to encoder: Encoder)`).
    private func isInsideCodableMethod(_ node: SwitchExprSyntax) -> Bool {
        var current: Syntax? = Syntax(node)
        while let parent = current?.parent {
            if let initDecl = parent.as(InitializerDeclSyntax.self) {
                let params = initDecl.signature.parameterClause.parameters
                if params.contains(where: { paramLooksLikeDecoder($0) }) {
                    return true
                }
            }
            if let funcDecl = parent.as(FunctionDeclSyntax.self) {
                if funcDecl.name.text == "encode" {
                    let params = funcDecl.signature.parameterClause.parameters
                    if params.contains(where: { paramLooksLikeEncoder($0) }) {
                        return true
                    }
                }
            }
            current = parent
        }
        return false
    }

    private func paramLooksLikeDecoder(_ param: FunctionParameterSyntax) -> Bool {
        let typeText = param.type.trimmedDescription
        return typeText == "Decoder" || typeText.hasSuffix(".Decoder")
    }

    private func paramLooksLikeEncoder(_ param: FunctionParameterSyntax) -> Bool {
        let typeText = param.type.trimmedDescription
        return typeText == "Encoder" || typeText.hasSuffix(".Encoder")
    }
}
