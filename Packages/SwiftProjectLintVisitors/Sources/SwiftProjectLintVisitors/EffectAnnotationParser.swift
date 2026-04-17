import SwiftSyntax

/// Declared idempotency effect for a function, parsed from `/// @lint.effect` doc comments.
///
/// Phase 1 of the idempotency trial recognises three tiers: `idempotent`, `observational`,
/// and `non_idempotent`. `observational` was promoted into the lattice to resolve OI-5 —
/// see the Formalized Effect Lattice section of the proposal. Remaining tiers (`pure`,
/// `transactional_idempotent`, `externally_idempotent`, `unknown`) stay out of scope and
/// are treated as unrecognised — see `docs/phase1/trial-scope.md` in the
/// swiftIdempotency repo.
public enum DeclaredEffect: Sendable, Equatable {
    case idempotent
    case observational
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

    /// Reads the `@lint.effect` tier declared on a node, if any.
    public static func parseEffect(leadingTrivia: Trivia) -> DeclaredEffect? {
        for line in docCommentLines(from: leadingTrivia) {
            if let effect = extractEffect(from: line) {
                return effect
            }
        }
        return nil
    }

    /// Reads the `@lint.context` kind declared on a node, if any.
    public static func parseContext(leadingTrivia: Trivia) -> ContextEffect? {
        for line in docCommentLines(from: leadingTrivia) {
            if let context = extractContext(from: line) {
                return context
            }
        }
        return nil
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
        var s = self
        while let c = s.first, c == " " || c == "\t" { s = s.dropFirst() }
        return s
    }

    func firstWord() -> String {
        var out = ""
        for c in self {
            if c.isWhitespace { break }
            // Stop at grammar separators that would indicate sub-directives we don't handle.
            if c == "(" || c == ":" { break }
            out.append(c)
        }
        return out
    }
}
