import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `(a, b) == (c, d)` / `!=` tuple-literal equality where any element
/// on either side is an "unstable" read — `Date()`, `UUID()`, `.now`,
/// `Int.random(in:)`, `CFAbsoluteTimeGetCurrent()`, or a parameter/identifier
/// conventionally named after an unstable value (`now`, `timestamp`, `nonce`).
///
/// ## Why
/// Tuple equality is structural: the comparison succeeds only when every
/// positional element is `==`. When one element is produced by a time,
/// randomness, or per-call identity source, the comparison almost never
/// converges on replay — which is exactly what breaks caching, memoisation,
/// idempotency guards, and change-detection patterns like:
///
///     if (input, Date()) == previousInput { return cached }
///
/// The equality check here can only fail, so the guard is dead code — or
/// the guard is live but tests the wrong thing. Either way, a structural
/// tuple with an unstable component has no defensible semantic reading.
///
/// ## Scope
/// - **File-local.** No cross-file resolution, no annotation requirement —
///   this rule fires on the shape alone.
/// - **Literal tuples only.** The visitor only inspects
///   `SequenceExprSyntax` with the shape `[TupleExpr, ==/!=, TupleExpr]`,
///   because it can't see through variable references without type
///   resolution. `tupleA == tupleB` where the tuples are stored in
///   variables is silently skipped.
/// - **Arity ≥ 2.** A single-element parenthesised expression `(x)` is
///   not a tuple; `(x, y)` and wider are.
/// - **Conservative heuristics.** Constructor calls (`Date()`, `UUID()`),
///   member-access reads on well-known clock types (`Date.now`,
///   `ContinuousClock.now`), explicit `.random` calls on numeric types,
///   and a short whitelist of identifier names. Identifier heuristics are
///   deliberately narrow — `date` / `id` / `time` on their own are too
///   ambiguous and are NOT flagged.
final class TupleEqualityWithUnstableComponentsVisitor: BasePatternVisitor {

    private var currentFilePath: String = ""

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        currentFilePath = filePath
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        guard let match = Self.tupleEqualityMatch(node) else {
            return .visitChildren
        }

        let lhsReasons = unstableReasons(in: match.lhs)
        let rhsReasons = unstableReasons(in: match.rhs)
        let reasons = lhsReasons + rhsReasons
        guard reasons.isEmpty == false else { return .visitChildren }

        let uniqueReasons = Array(Set(reasons)).sorted()
        let reasonList = uniqueReasons.joined(separator: ", ")

        addIssue(
            severity: pattern.severity,
            message: "Tuple equality carries unstable component(s): \(reasonList). "
                + "Structural equality on tuples containing time, randomness, or "
                + "per-call identity never converges on replay, so this comparison "
                + "either always fails or tests the wrong thing.",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Compare only the stable subset of fields, or promote the "
                + "tuple to a struct with an `Equatable` conformance tailored to the "
                + "semantic identity you actually want to compare.",
            ruleName: .tupleEqualityWithUnstableComponents
        )
        return .visitChildren
    }

    // MARK: - Shape match

    private struct TupleEqualityMatch {
        let lhs: TupleExprSyntax
        let rhs: TupleExprSyntax
    }

    /// Matches `(a, b, ...) ==/!= (c, d, ...)` in the unfolded SequenceExpr
    /// form. Both tuples must have arity ≥ 2; single-element paren
    /// expressions are not tuples.
    private static func tupleEqualityMatch(
        _ node: SequenceExprSyntax
    ) -> TupleEqualityMatch? {
        let elements = Array(node.elements)
        guard elements.count == 3,
              let opExpr = elements[1].as(BinaryOperatorExprSyntax.self),
              equalityOperators.contains(opExpr.operator.text),
              let lhs = elements[0].as(TupleExprSyntax.self),
              let rhs = elements[2].as(TupleExprSyntax.self),
              lhs.elements.count >= 2,
              rhs.elements.count >= 2 else {
            return nil
        }
        return TupleEqualityMatch(lhs: lhs, rhs: rhs)
    }

    // MARK: - Unstable element detection

    private func unstableReasons(in tuple: TupleExprSyntax) -> [String] {
        tuple.elements.compactMap { element in
            unstableReason(for: element.expression)
        }
    }

    private func unstableReason(for expr: ExprSyntax) -> String? {
        if let call = expr.as(FunctionCallExprSyntax.self) {
            return unstableReason(forCall: call)
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return unstableReason(forMemberAccess: member)
        }
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return unstableReason(forIdentifier: ref.baseName.text)
        }
        return nil
    }

    /// Constructor calls: `Date()`, `UUID()`, `CFAbsoluteTimeGetCurrent()`,
    /// and numeric `.random(in:)` / `.random()` reads.
    private func unstableReason(forCall call: FunctionCallExprSyntax) -> String? {
        if let bare = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            let name = bare.baseName.text
            if Self.unstableZeroArgConstructors.contains(name), call.arguments.isEmpty {
                return "\(name)()"
            }
            if Self.unstableZeroArgFunctions.contains(name), call.arguments.isEmpty {
                return "\(name)()"
            }
            return nil
        }
        guard let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              let base = member.base?.as(DeclReferenceExprSyntax.self) else {
            return nil
        }
        let methodName = member.declName.baseName.text
        let baseName = base.baseName.text
        if methodName == "now",
           Self.clockLikeTypeNames.contains(baseName),
           call.arguments.isEmpty {
            return "\(baseName).now()"
        }
        if methodName == "random",
           Self.randomReceiverTypeNames.contains(baseName) {
            return "\(baseName).random(...)"
        }
        return nil
    }

    /// Property-style reads: `Date.now`, `ContinuousClock.now`, etc.
    /// Un-based `.now` (leading-dot syntax with inferred base) is NOT
    /// flagged — without type resolution the base is unknown.
    private func unstableReason(forMemberAccess member: MemberAccessExprSyntax) -> String? {
        guard member.declName.baseName.text == "now",
              let base = member.base?.as(DeclReferenceExprSyntax.self),
              Self.clockLikeTypeNames.contains(base.baseName.text) else {
            return nil
        }
        return "\(base.baseName.text).now"
    }

    /// Bare-identifier heuristic: names that are, by near-universal
    /// convention, unstable-on-read. Kept deliberately short — `date`,
    /// `time`, and `id` are too ambiguous (many stable stored values
    /// carry those names) and are NOT in this set.
    private func unstableReason(forIdentifier name: String) -> String? {
        Self.unstableIdentifierNames.contains(name) ? "'\(name)'" : nil
    }

    // MARK: - Heuristic tables

    private static let equalityOperators: Set<String> = ["==", "!="]

    private static let unstableZeroArgConstructors: Set<String> = ["Date", "UUID"]

    private static let unstableZeroArgFunctions: Set<String> = [
        "CFAbsoluteTimeGetCurrent",
        "mach_absolute_time"
    ]

    private static let clockLikeTypeNames: Set<String> = [
        "Date",
        "DispatchTime",
        "ContinuousClock",
        "SuspendingClock"
    ]

    private static let randomReceiverTypeNames: Set<String> = [
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Double", "Float", "Float16", "Float32", "Float64",
        "CGFloat", "Bool"
    ]

    private static let unstableIdentifierNames: Set<String> = [
        "now", "timestamp", "nonce"
    ]
}
