import SwiftSyntax

/// Declared idempotency effect for a function, parsed from `/// @lint.effect` doc comments.
///
/// Phase 1 of the idempotency trial recognised three tiers: `idempotent`,
/// `observational`, and `non_idempotent`. Phase 2 introduces `externally_idempotent`
/// for functions that are idempotent *only if* routed through a caller-supplied
/// deduplication key — the characteristic shape of Stripe / SES / SNS / Mailgun
/// APIs that accept a client-provided idempotency token. The key-routing check
/// itself is deferred to a follow-up rule (`missingIdempotencyKey`); Phase 2's
/// tier-introduction commit treats the key as assumed-routed at call sites that
/// do not involve `observational` callers or `non_idempotent` callees.
///
/// Remaining tiers (`pure`, `transactional_idempotent`, `unknown`) stay out of
/// scope and are treated as unrecognised — see `docs/phase1/trial-scope.md`.
public enum DeclaredEffect: Sendable, Equatable {
    case idempotent
    case observational
    case externallyIdempotent
    case nonIdempotent
}

/// Declared execution context for a function, parsed from `/// @lint.context` doc comments.
///
/// `replayable` and `retry_safe` are semantically equivalent to the linter —
/// both impose "callees must be idempotent" on the body. Only the documentation
/// intent differs. `once` and `dedup_guarded` are out of scope for Phase 1.
public enum ContextEffect: Sendable, Equatable {
    case replayable
    case retrySafe
}

/// Parses `/// @lint.effect <tier>` and `/// @lint.context <kind>` from the doc-comment
/// leading trivia of a Swift declaration.
///
/// Deliberately forgiving: unknown tokens are silently ignored rather than diagnosed,
/// because grammar versioning (`unknownAnnotationVersion`) is explicitly out of scope
/// for Phase 1 of the trial.
public enum EffectAnnotationParser {

    /// Reads the `@lint.effect` tier declared on a node, if any. Scans only
    /// the supplied trivia; callers with a whole `FunctionDeclSyntax` should
    /// prefer `parseEffect(declaration:)`, which collects trivia from all
    /// positions a doc comment can legitimately live (OI-7).
    public static func parseEffect(leadingTrivia: Trivia) -> DeclaredEffect? {
        for line in docCommentLines(from: leadingTrivia) {
            if let effect = extractEffect(from: line) {
                return effect
            }
        }
        return nil
    }

    /// Reads the `@lint.context` kind declared on a node, if any. Scans only
    /// the supplied trivia; callers with a whole `FunctionDeclSyntax` should
    /// prefer `parseContext(declaration:)`.
    public static func parseContext(leadingTrivia: Trivia) -> ContextEffect? {
        for line in docCommentLines(from: leadingTrivia) {
            if let context = extractContext(from: line) {
                return context
            }
        }
        return nil
    }

    /// Reads the `@lint.effect` tier declared on a function, tolerating
    /// the doc comment's position relative to attributes and modifiers.
    ///
    /// `FunctionDeclSyntax.leadingTrivia` only covers trivia before the
    /// declaration's first token — which, when attributes are present, is the
    /// first attribute's `@`. Doc comments that sit *between* an attribute and
    /// the function keyword, or between an attribute and a modifier, land in
    /// a different trivia position (attribute trailing trivia, modifier
    /// leading trivia, or `funcKeyword` leading trivia). This overload
    /// collects from every such position so annotations are read regardless
    /// of ordering (see OI-7).
    public static func parseEffect(declaration: FunctionDeclSyntax) -> DeclaredEffect? {
        parseEffect(leadingTrivia: combinedDocTrivia(for: declaration))
    }

    /// Reads the `@lint.context` kind declared on a function, tolerating the
    /// doc comment's position relative to attributes and modifiers. See
    /// `parseEffect(declaration:)` for the full reasoning.
    public static func parseContext(declaration: FunctionDeclSyntax) -> ContextEffect? {
        parseContext(leadingTrivia: combinedDocTrivia(for: declaration))
    }

    /// Combines trivia from every position in a function declaration's header
    /// where a user-authored doc comment could legitimately sit: before the
    /// first token, after any attribute, before any modifier, and before the
    /// `func` keyword. Source order is preserved so the parser's first-match
    /// semantics pick up the earliest annotation the user wrote.
    ///
    /// ## Orderings handled
    /// ```
    /// /// @lint.context replayable
    /// @available(macOS 13.0, *)
    /// public func foo() { }            // captured by decl.leadingTrivia
    ///
    /// @available(macOS 13.0, *)
    /// /// @lint.context replayable
    /// public func foo() { }            // captured by modifier leading trivia
    ///
    /// @available(macOS 13.0, *)
    /// /// @lint.context replayable
    /// func foo() { }                   // captured by funcKeyword leading trivia
    /// ```
    static func combinedDocTrivia(for decl: FunctionDeclSyntax) -> Trivia {
        var pieces: [TriviaPiece] = []
        pieces.append(contentsOf: decl.leadingTrivia)
        for attribute in decl.attributes {
            // Each attribute's own leading/trailing trivia. Leading trivia of
            // the FIRST attribute is the same content as `decl.leadingTrivia`
            // (duplication accepted — the parser returns the first match, so
            // re-scanning identical content is wasteful but not incorrect).
            // Leading trivia of later attributes is where a doc comment
            // between two attributes lands.
            pieces.append(contentsOf: attribute.leadingTrivia)
            pieces.append(contentsOf: attribute.trailingTrivia)
        }
        for modifier in decl.modifiers {
            pieces.append(contentsOf: modifier.leadingTrivia)
        }
        pieces.append(contentsOf: decl.funcKeyword.leadingTrivia)
        return Trivia(pieces: pieces)
    }

    private static func docCommentLines(from trivia: Trivia) -> [String] {
        trivia.compactMap { piece -> String? in
            switch piece {
            case .docLineComment(let text):
                return text
            case .docBlockComment(let text):
                return text
            default:
                return nil
            }
        }
    }

    private static func extractEffect(from line: String) -> DeclaredEffect? {
        guard let range = line.range(of: "@lint.effect") else { return nil }
        let rest = line[range.upperBound...].trimmingLeadingWhitespace()
        let token = rest.firstWord()
        switch token {
        case "idempotent":
            return .idempotent
        case "observational":
            return .observational
        case "externally_idempotent":
            return .externallyIdempotent
        case "non_idempotent":
            return .nonIdempotent
        default:
            return nil
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
        default:
            return nil
        }
    }
}

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
            // Stop at grammar separators that would indicate sub-directives we don't handle.
            if char == "(" || char == ":" { break }
            out.append(char)
        }
        return out
    }
}
