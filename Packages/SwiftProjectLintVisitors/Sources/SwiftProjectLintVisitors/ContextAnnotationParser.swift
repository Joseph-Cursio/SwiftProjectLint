import SwiftEffectInference
import SwiftSyntax

/// Declared execution context for a function, parsed from `/// @lint.context` doc comments.
///
/// - `replayable` / `retry_safe` are semantically equivalent to the linter:
///   both impose "callees must be idempotent" on the body. Only the
///   documentation intent differs. The `nonIdempotentInRetryContext` rule
///   fires on callees declared/inferred `non_idempotent`; unannotated
///   callees stay silent (precision-preserving default).
/// - `strictReplayable` is the opt-in strict variant of `replayable`. The
///   additional `unannotatedInStrictReplayableContext` rule fires on
///   callees whose effect can't be proven idempotent/observational —
///   "flag unless you know for sure." Adopters promote critical
///   handlers to this tier and leave less-critical ones on `replayable`.
/// - `once` is the inverse contract: the function asserts that it must run
///   at most once across all replays, retries, or iterations. The
///   `onceContractViolation` rule fires when a `@context once` callee
///   appears in a position where it could be re-invoked (loop body,
///   `replayable` / `retry_safe` / `strict_replayable` caller).
/// - `dedup_guarded` remains out of scope.
public enum ContextEffect: Sendable, Equatable {
    case replayable
    case retrySafe
    case once
    case strictReplayable
}

/// Parses `/// @lint.context <kind>` — the *execution-context* axis.
///
/// This axis is the linter's own, and stays here. `SwiftEffectInference` owns the
/// orthogonal *effect* axis (`@lint.effect`, the `@Idempotent` family, the lattice) and is the
/// single oracle for it; nothing about a retry context belongs in a library whose other
/// consumer, `swift-infer`, has no notion of one.
///
/// What this parser deliberately does *not* re-implement is the doc-comment plumbing —
/// which trivia a comment actually lands in, and how to read a token off a line. Both come
/// from `SwiftEffectInference.EffectAnnotationParser`. That plumbing is subtle (SwiftSyntax
/// attaches a doc comment above an attributed declaration to the *attribute*, not to the
/// `func` keyword), and a second copy of it here is exactly how the previous fork began.
public enum ContextAnnotationParser {

    /// Reads the `@lint.context` kind declared on a node, if any. Scans only the supplied
    /// trivia; callers holding a whole declaration should prefer `parseContext(declaration:)`.
    public static func parseContext(leadingTrivia: Trivia) -> ContextEffect? {
        for line in EffectAnnotationParser.documentationLines(in: leadingTrivia) {
            if let context = extractContext(from: line) {
                return context
            }
        }
        return nil
    }

    /// Reads the `@lint.context` kind declared on a function.
    public static func parseContext(declaration: FunctionDeclSyntax) -> ContextEffect? {
        parseContext(leadingTrivia: EffectAnnotationParser.documentationTrivia(for: declaration))
    }

    /// Reads the `@lint.context` kind declared on a variable binding.
    public static func parseContext(declaration: VariableDeclSyntax) -> ContextEffect? {
        parseContext(leadingTrivia: EffectAnnotationParser.documentationTrivia(for: declaration))
    }

    /// Reads the `@lint.context` kind that applies to a call site, tolerating prefix-statement
    /// placements that SwiftSyntax binds to a keyword token rather than to the call expression.
    ///
    /// The call's own `leadingTrivia` catches the direct idiom
    /// `/// @lint.context replayable\napp.post(...) { req in ... }`. But adopter code often wraps
    /// the annotated call in a prefix statement — `return .run { ... }`, `try foo { ... }`,
    /// `let x = bar { ... }`, or a ternary branch `? a : .run { ... }`. In those cases SwiftSyntax
    /// attaches the doc comment to the keyword (`return`, `try`, `await`, `let`) or to the ternary
    /// `:`, not to the call's first token. An implementation that checked only the call's own
    /// leading trivia silently missed these placements, yielding zero diagnostics on 100% of
    /// TCA-style reducer effects — hence the scan back through the enclosing code-block item.
    public static func parseContextAtCallSite(
        of call: FunctionCallExprSyntax
    ) -> ContextEffect? {
        if let context = parseContext(leadingTrivia: call.leadingTrivia) {
            return context
        }

        var cursor: Syntax? = Syntax(call).parent
        var enclosingItem: CodeBlockItemSyntax?
        while let node = cursor {
            if let item = node.as(CodeBlockItemSyntax.self) {
                enclosingItem = item
                break
            }
            cursor = node.parent
        }
        guard let enclosingItem else { return nil }

        let callStart = call.positionAfterSkippingLeadingTrivia
        var mostRecent: ContextEffect?
        for token in enclosingItem.tokens(viewMode: .sourceAccurate) {
            if token.position >= callStart { break }
            if let context = parseContext(leadingTrivia: token.leadingTrivia) {
                mostRecent = context
            }
        }
        return mostRecent
    }

    // MARK: - Private

    private static func extractContext(from line: String) -> ContextEffect? {
        switch EffectAnnotationParser.token(after: "@lint.context", in: line) {
        case "replayable":
            return .replayable

        case "retry_safe":
            return .retrySafe

        case "once":
            return .once

        case "strict_replayable":
            return .strictReplayable

        default:
            return nil
        }
    }
}
