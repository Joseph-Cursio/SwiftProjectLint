import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects a `switch` case for an enum case whose **name** implies an
/// idempotent action — exact `dismiss` / `close` / `hide` / `select` /
/// `cancel`, or prefix `set…` / `show…` / `select…` — whose **body**
/// mutates non-idempotently: a compound assignment (`+=`, `-=`, `*=`,
/// `/=`, `%=`) or a `.toggle()` call.
///
/// ## Why
/// An action named like a set/dismiss/close is, by its name, a contract
/// that applying it twice equals applying it once (`reduce(reduce(s, a), a)
/// == reduce(s, a)`). A body that accumulates (`badge += 1`) or flips
/// (`isOn.toggle()`) breaks that contract — the name lies. This is the
/// exact class of mislabel that motivated SwiftInferProperties' measured
/// idempotence verification (a `setBadge` that increments; a `hide` that
/// toggles); catching it statically gives fast feedback before the
/// (expensive) execution-based check.
///
/// ## Scope
/// - **Enum-case switches only.** The case label must reference a leading
///   `.name` enum-case pattern (the `switch action { case .x: … }` shape),
///   so plain value switches aren't matched.
/// - **Synchronous body only.** The scan does not descend into closures
///   (`ClosureExprSyntax`), so a `+=` inside a returned effect
///   (`.run { … }`) — which isn't the synchronous state reduction — is not
///   flagged.
/// - **Shape-based, file-local.** No type resolution; matches on the case
///   name + a non-idempotent operator/`.toggle()` in the arm.
final class NonIdempotentActionNameVisitor: BasePatternVisitor {

    private var currentFilePath: String = ""

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        currentFilePath = filePath
    }

    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        guard let caseName = idempotentSoundingCaseName(in: node) else {
            return .visitChildren
        }
        guard let op = nonIdempotentOperation(in: Syntax(node.statements)) else {
            return .visitChildren
        }
        addIssue(
            severity: pattern.severity,
            message: "Action `.\(caseName)` is named like an idempotent action but its "
                + "body mutates non-idempotently (`\(op)`). Applying it twice would not "
                + "equal applying it once.",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Make the body idempotent (assign a fixed value instead of "
                + "accumulating/toggling), or rename the action to reflect that it "
                + "mutates cumulatively (e.g. `increment`, `toggleX`).",
            ruleName: .nonIdempotentActionName
        )
        return .visitChildren
    }

    // MARK: - Case-name match

    /// The leading enum-case name of this `switch` case if it sounds
    /// idempotent, else `nil`. Handles `.dismiss`, `.set…(let x)`,
    /// `let .set…(x)` — any pattern whose first base-less `.name` member
    /// access matches the witness vocabulary.
    private func idempotentSoundingCaseName(in node: SwitchCaseSyntax) -> String? {
        guard let label = node.label.as(SwitchCaseLabelSyntax.self) else { return nil }
        for item in label.caseItems {
            guard let name = leadingCaseName(in: Syntax(item.pattern)) else { continue }
            if soundsIdempotent(name) { return name }
        }
        return nil
    }

    private func leadingCaseName(in syntax: Syntax) -> String? {
        if let member = syntax.as(MemberAccessExprSyntax.self), member.base == nil {
            return member.declName.baseName.text
        }
        for child in syntax.children(viewMode: .sourceAccurate) {
            if let found = leadingCaseName(in: child) { return found }
        }
        return nil
    }

    private func soundsIdempotent(_ name: String) -> Bool {
        if Self.exactWitnesses.contains(name) { return true }
        return Self.prefixWitnesses.contains { name.hasPrefix($0) }
    }

    // MARK: - Non-idempotent body detection

    /// The first non-idempotent operation in this subtree (a compound-
    /// assignment operator or a `.toggle()` call), not descending into
    /// closures (effect bodies). Returns its textual form for the message.
    private func nonIdempotentOperation(in syntax: Syntax) -> String? {
        if syntax.is(ClosureExprSyntax.self) { return nil }
        if let op = syntax.as(BinaryOperatorExprSyntax.self),
           Self.compoundAssignOperators.contains(op.operator.text) {
            return op.operator.text
        }
        if let call = syntax.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "toggle",
           call.arguments.isEmpty,
           member.base != nil {
            return ".toggle()"
        }
        for child in syntax.children(viewMode: .sourceAccurate) {
            if let found = nonIdempotentOperation(in: child) { return found }
        }
        return nil
    }

    // MARK: - Vocabulary

    private static let exactWitnesses: Set<String> = [
        "dismiss", "close", "hide", "select", "cancel"
    ]

    private static let prefixWitnesses: [String] = ["set", "show", "select"]

    private static let compoundAssignOperators: Set<String> = [
        "+=", "-=", "*=", "/=", "%="
    ]
}
