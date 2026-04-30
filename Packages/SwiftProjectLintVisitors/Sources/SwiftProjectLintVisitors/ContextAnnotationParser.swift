import SwiftSyntax

/// Declared execution context for a function, parsed from `/// @lint.context`
/// doc comments. SwiftProjectLint-specific concern (gates which lint rules
/// fire); kept here rather than in `SwiftEffectInference` per
/// `docs/SwiftEffectInference Design v0.2.md` §6.
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

/// Parses `/// @lint.context <kind>` from the doc-comment leading trivia of
/// a Swift declaration. Deliberately forgiving: unknown tokens are silently
/// ignored rather than diagnosed.
///
/// Effect parsing (`/// @lint.effect`, `@Idempotent` etc.) lives in
/// `SwiftEffectInference.EffectAnnotationParser` — both grammars used to
/// share a single parser file in SPL; the migration extracted the effect
/// half into the shared core and left the SPL-specific context half here.
public enum ContextAnnotationParser {

    /// Reads the `@lint.context` kind declared on a node, if any. Scans only
    /// the supplied trivia; callers with a whole declaration should prefer
    /// the function-decl / variable-decl overloads.
    public static func parseContext(leadingTrivia: Trivia) -> ContextEffect? {
        for line in docCommentLines(from: leadingTrivia) {
            if let context = extractContext(from: line) {
                return context
            }
        }
        return nil
    }

    /// Reads the `@lint.context` kind that applies to a call site, tolerating
    /// prefix-statement placements that SwiftSyntax binds to a keyword token
    /// rather than to the call expression itself.
    ///
    /// The call's own `leadingTrivia` catches the direct idiom
    /// `/// @lint.context replayable\napp.post(...) { req in ... }`. But
    /// adopter code often wraps the annotated call in a prefix statement —
    /// `return .run { ... }`, `try foo { ... }`, `let x = bar { ... }`, or a
    /// ternary branch `? a : .run { ... }`. In those cases SwiftSyntax
    /// attaches the doc comment to the keyword (`return`, `try`, `await`,
    /// `let`) or to the ternary `:`, not to the call's first token. The
    /// earlier implementation checked only the call's own leading trivia
    /// and silently missed these placements, yielding zero diagnostics on
    /// 100% of TCA-style reducer effects.
    ///
    /// Policy: the enclosing `CodeBlockItemSyntax` bounds the search.
    /// Within that statement, the most recent doc-comment annotation that
    /// precedes the call (in source order) wins. Unrelated annotations in
    /// earlier statements are isolated by the CodeBlockItem boundary.
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

    /// Reads the `@lint.context` kind declared on a function, tolerating the
    /// doc comment's position relative to attributes and modifiers.
    public static func parseContext(declaration: FunctionDeclSyntax) -> ContextEffect? {
        parseContext(leadingTrivia: combinedDocTrivia(for: declaration))
    }

    /// Reads the `@lint.context` kind declared on a variable binding.
    public static func parseContext(declaration: VariableDeclSyntax) -> ContextEffect? {
        parseContext(leadingTrivia: combinedDocTrivia(for: declaration))
    }

    // MARK: - Combined doc-trivia helpers
    //
    // Duplicated from `SwiftEffectInference.EffectAnnotationParser` rather
    // than imported — those helpers are internal to the shared core and the
    // duplication cost is low (~25 lines of static code).

    private static func combinedDocTrivia(for decl: FunctionDeclSyntax) -> Trivia {
        var pieces: [TriviaPiece] = []
        pieces.append(contentsOf: decl.leadingTrivia)
        for attribute in decl.attributes {
            pieces.append(contentsOf: attribute.leadingTrivia)
            pieces.append(contentsOf: attribute.trailingTrivia)
        }
        for modifier in decl.modifiers {
            pieces.append(contentsOf: modifier.leadingTrivia)
        }
        pieces.append(contentsOf: decl.funcKeyword.leadingTrivia)
        return Trivia(pieces: pieces)
    }

    private static func combinedDocTrivia(for decl: VariableDeclSyntax) -> Trivia {
        var pieces: [TriviaPiece] = []
        pieces.append(contentsOf: decl.leadingTrivia)
        for attribute in decl.attributes {
            pieces.append(contentsOf: attribute.leadingTrivia)
            pieces.append(contentsOf: attribute.trailingTrivia)
        }
        for modifier in decl.modifiers {
            pieces.append(contentsOf: modifier.leadingTrivia)
        }
        pieces.append(contentsOf: decl.bindingSpecifier.leadingTrivia)
        return Trivia(pieces: pieces)
    }

    private static func docCommentLines(from trivia: Trivia) -> [String] {
        trivia.compactMap { piece -> String? in
            switch piece {
            case .docLineComment(let text), .docBlockComment(let text):
                return text
            default:
                return nil
            }
        }
    }

    private static func extractContext(from line: String) -> ContextEffect? {
        guard let range = line.range(of: "@lint.context") else { return nil }
        let rest = line[range.upperBound...].trimmingLeadingWhitespace()
        let token = rest.firstWord()
        switch token {
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

// MARK: - Substring helpers

private extension Substring {

    func trimmingLeadingWhitespace() -> Substring {
        var slice = self
        while let char = slice.first, char == " " || char == "\t" { slice = slice.dropFirst() }
        return slice
    }

    func firstWord() -> String {
        var out = ""
        for char in self {
            if char.isWhitespace { break }
            if char == "(" || char == ":" { break }
            out.append(char)
        }
        return out
    }
}
