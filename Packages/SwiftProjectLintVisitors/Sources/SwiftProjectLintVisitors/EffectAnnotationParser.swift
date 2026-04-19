import SwiftSyntax

/// Declared idempotency effect for a function, parsed from `/// @lint.effect` doc comments.
///
/// Phase 1 of the idempotency trial recognised three tiers: `idempotent`,
/// `observational`, and `non_idempotent`. Phase 2 introduced `externally_idempotent`
/// for functions that are idempotent *only if* routed through a caller-supplied
/// deduplication key — the characteristic shape of Stripe / SES / SNS / Mailgun
/// APIs that accept a client-provided idempotency token.
///
/// Phase 2.1 added the `(by: paramName)` qualifier to name the specific parameter
/// that carries the key. When present, the `missingIdempotencyKey` rule verifies
/// that call sites pass a stable value at the named parameter. When absent, the
/// tier's lattice behaviour still applies but no key-routing verification runs —
/// the annotation is documentary.
///
/// Remaining tiers (`pure`, `transactional_idempotent`, `unknown`) stay out of
/// scope and are treated as unrecognised — see `docs/phase1/trial-scope.md`.
public enum DeclaredEffect: Sendable, Equatable {
    case idempotent
    case observational
    /// - Parameter keyParameter: the external label of the parameter that
    ///   holds the deduplication key, if the declaration specified one via
    ///   `(by: paramName)`. `nil` when unspecified — the annotation then has
    ///   lattice behaviour only.
    case externallyIdempotent(keyParameter: String?)
    case nonIdempotent
}

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

    /// Reads the `@lint.context` kind that applies to a call site, tolerating
    /// prefix-statement placements that SwiftSyntax binds to a keyword token
    /// rather than to the call expression itself.
    ///
    /// The call's own `leadingTrivia` catches the direct idiom
    /// `/// @lint.context replayable\napp.post(...) { req in ... }`. But adopter
    /// code often wraps the annotated call in a prefix statement —
    /// `return .run { ... }`, `try foo { ... }`, `let x = bar { ... }`, or a
    /// ternary branch `? a : .run { ... }`. In those cases SwiftSyntax attaches
    /// the doc comment to the keyword (`return`, `try`, `await`, `let`) or to
    /// the ternary `:`, not to the call's first token. The earlier implementation
    /// checked only the call's own leading trivia and silently missed these
    /// placements, yielding zero diagnostics on 100% of TCA-style reducer
    /// effects.
    ///
    /// Policy: the enclosing `CodeBlockItemSyntax` bounds the search. Within
    /// that statement, the most recent doc-comment annotation that precedes
    /// the call (in source order) wins. Unrelated annotations in earlier
    /// statements are isolated by the CodeBlockItem boundary.
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

    /// Reads the `@lint.effect` tier declared on a function. Considers
    /// both doc-comment annotations (`/// @lint.effect idempotent`) and
    /// attribute-form annotations emitted by the `SwiftIdempotency` macros
    /// package (`@Idempotent`, `@NonIdempotent`, `@Observational`,
    /// `@ExternallyIdempotent(by:)`).
    ///
    /// `FunctionDeclSyntax.leadingTrivia` only covers trivia before the
    /// declaration's first token — which, when attributes are present, is the
    /// first attribute's `@`. Doc comments that sit *between* an attribute and
    /// the function keyword, or between an attribute and a modifier, land in
    /// a different trivia position (attribute trailing trivia, modifier
    /// leading trivia, or `funcKeyword` leading trivia). This overload
    /// collects from every such position so annotations are read regardless
    /// of ordering (see OI-7).
    ///
    /// When both forms are present and agree, that effect is returned. When
    /// both forms disagree, returns `nil` (collision-withdraw semantics
    /// matching OI-4 — two conflicting user-authored signals on the same
    /// declaration express ambiguity the parser will not paper over).
    public static func parseEffect(declaration: FunctionDeclSyntax) -> DeclaredEffect? {
        let attributeEffect = effectFromAttributes(declaration.attributes)
        let docCommentEffect = parseEffect(leadingTrivia: combinedDocTrivia(for: declaration))
        return resolveEffectSignals(attribute: attributeEffect, docComment: docCommentEffect)
    }

    /// Reads the `@lint.context` kind declared on a function, tolerating the
    /// doc comment's position relative to attributes and modifiers. See
    /// `parseEffect(declaration:)` for the full reasoning.
    public static func parseContext(declaration: FunctionDeclSyntax) -> ContextEffect? {
        parseContext(leadingTrivia: combinedDocTrivia(for: declaration))
    }

    /// Reads the `@lint.effect` tier declared on a variable binding,
    /// tolerating doc-comment position the same way the function overload
    /// does. Also recognises attribute-form annotations (`@Idempotent`
    /// etc.) emitted by the `SwiftIdempotency` macros package. Annotations
    /// on non-closure bindings (`let x: Int = 5`) parse identically —
    /// callers decide whether the binding's initialiser makes the
    /// annotation semantically meaningful; this parser is content-blind.
    ///
    /// Collision semantics identical to the function-decl overload.
    public static func parseEffect(declaration: VariableDeclSyntax) -> DeclaredEffect? {
        let attributeEffect = effectFromAttributes(declaration.attributes)
        let docCommentEffect = parseEffect(leadingTrivia: combinedDocTrivia(for: declaration))
        return resolveEffectSignals(attribute: attributeEffect, docComment: docCommentEffect)
    }

    /// Reads the `@lint.context` kind declared on a variable binding.
    public static func parseContext(declaration: VariableDeclSyntax) -> ContextEffect? {
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

    /// Same combining strategy as the function-decl overload, but for
    /// variable declarations. Collects every trivia position where a
    /// user-authored doc comment can legitimately sit relative to
    /// attributes and modifiers of a `let` / `var` binding.
    static func combinedDocTrivia(for decl: VariableDeclSyntax) -> Trivia {
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

    /// Resolves a declaration's effect when both an attribute-form and a
    /// doc-comment-form signal may be present.
    ///
    /// - Neither present → nil
    /// - One present → that one
    /// - Both present and agree → that tier
    /// - Both present and disagree → nil (collision-withdraw, matching the
    ///   cross-file OI-4 semantics for same-signature conflicts)
    static func resolveEffectSignals(
        attribute: DeclaredEffect?,
        docComment: DeclaredEffect?
    ) -> DeclaredEffect? {
        switch (attribute, docComment) {
        case (nil, nil): return nil
        case (let a?, nil): return a
        case (nil, let d?): return d
        case (let a?, let d?): return a == d ? a : nil
        }
    }

    /// Scans an attribute list for `@Idempotent`, `@NonIdempotent`,
    /// `@Observational`, or `@ExternallyIdempotent(by:)` and returns the
    /// corresponding `DeclaredEffect`. Returns nil when no recognised
    /// attribute is present.
    ///
    /// `@IdempotencyTests` is also recognised but carries no effect —
    /// it's a test-generation attribute on `@Suite` types, not a
    /// function-effect declaration.
    ///
    /// Only inspects attribute names verbatim — no macro expansion is
    /// consulted. This means the parser works independently of whether the
    /// `SwiftIdempotency` package is in the build; the attributes are
    /// recognised by name alone. Users who write `@Idempotent` without
    /// importing the macros package get linter coverage but not the
    /// compile-time / test-time behaviour.
    static func effectFromAttributes(_ attributes: AttributeListSyntax) -> DeclaredEffect? {
        for element in attributes {
            guard let attr = element.as(AttributeSyntax.self) else { continue }
            guard let typeName = attributeTypeName(attr.attributeName) else { continue }
            switch typeName {
            case "Idempotent":
                return .idempotent
            case "NonIdempotent":
                return .nonIdempotent
            case "Observational":
                return .observational
            case "ExternallyIdempotent":
                return .externallyIdempotent(keyParameter: extractByLabel(from: attr))
            case "IdempotencyTests":
                // Test-generation attribute on `@Suite` types (macros
                // package round-8 redesign). Carries no function-effect
                // semantics; listed here so the linter's recognised-
                // attribute surface explicitly covers it rather than
                // falling through as "unknown".
                continue
            default:
                continue
            }
        }
        return nil
    }

    /// Extracts the bare identifier name from an attribute's type syntax.
    /// Returns nil for complex types (member access, generic, etc.) that
    /// shouldn't be interpreted as effect attributes.
    private static func attributeTypeName(_ type: TypeSyntax) -> String? {
        type.as(IdentifierTypeSyntax.self)?.name.text
    }

    /// Extracts the `by:` labelled argument from an attribute's argument
    /// list, if present and a string literal. Returns nil when the
    /// argument is absent, not labelled `by:`, or not a string literal.
    /// Empty-string arguments normalise to nil so
    /// `@ExternallyIdempotent(by: "")` behaves identically to the
    /// label-omitting `@ExternallyIdempotent` form.
    private static func extractByLabel(from attr: AttributeSyntax) -> String? {
        guard case .argumentList(let args) = attr.arguments else { return nil }
        for arg in args {
            guard arg.label?.text == "by",
                  let strLit = arg.expression.as(StringLiteralExprSyntax.self),
                  strLit.segments.count == 1,
                  let segment = strLit.segments.first?.as(StringSegmentSyntax.self) else {
                continue
            }
            let text = segment.content.text
            return text.isEmpty ? nil : text
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
        case "externally_idempotent":
            // Look for an optional `(by: paramName)` qualifier immediately
            // following the tier token. Whitespace between the token and `(`
            // is tolerated.
            let afterToken = rest.dropFirst(token.count).trimmingLeadingWhitespace()
            return .externallyIdempotent(keyParameter: extractByQualifier(from: afterToken))
        case "non_idempotent":
            return .nonIdempotent
        default:
            return nil
        }
    }

    /// Extracts a `(by: paramName)` qualifier if present. Tolerates whitespace
    /// variants and ignores additional content inside the parens (e.g. a future
    /// `reason:` alongside). Returns `nil` when the qualifier is absent or
    /// malformed.
    private static func extractByQualifier(from text: Substring) -> String? {
        guard text.first == "(" else { return nil }
        let inside = text.dropFirst().trimmingLeadingWhitespace()
        guard inside.hasPrefix("by:") else { return nil }
        let afterBy = inside.dropFirst(3).trimmingLeadingWhitespace()
        let ident = afterBy.firstIdentifier()
        return ident.isEmpty ? nil : String(ident)
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

    /// Reads the longest prefix of identifier characters (letters, digits,
    /// underscore). Used by the `(by: paramName)` parser to lift out the
    /// parameter name from the rest of the annotation tail.
    func firstIdentifier() -> Substring {
        var end = startIndex
        for idx in indices {
            let char = self[idx]
            if char.isLetter || char.isNumber || char == "_" {
                end = index(after: idx)
            } else {
                break
            }
        }
        return self[startIndex..<end]
    }
}
