import SwiftSyntax

/// Reading a *name list* out of source — the shared vocabulary of the two rules that compare
/// such lists.
///
/// `ParallelEnumShape` reports lists that are **identical** (one concept, declared twice, not yet
/// diverged) and `ParallelListDrift` reports lists that are **nearly** identical (one concept,
/// already diverged). They must agree on what counts as a list and on when two spellings name the
/// same thing, or the pair of rules would disagree about the same two declarations — the very
/// failure they exist to detect.
enum NameListReader {

    /// Normalizes a name for comparison: case- and separator-insensitive, so `UIPatterns`,
    /// `uiPatterns` and `"ui-patterns"` all collapse to `uipatterns`.
    static func normalize(_ raw: String) -> String {
        raw.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The names in an array literal, when every element is name-like and all of one uniform
    /// kind. Returns nil for a mixed or non-name array — that is a data structure, not an
    /// enumeration of names.
    static func names(inArrayLiteral node: ArrayExprSyntax) -> [String]? {
        var names: [String] = []
        var kinds: Set<String> = []
        for element in node.elements {
            guard let (name, kind) = nameAndKind(of: element.expression) else { return nil }
            names.append(name)
            kinds.insert(kind)
        }
        guard kinds.count == 1 else { return nil }
        return names
    }

    /// The variable/property name an array literal is bound to, by walking up to the nearest
    /// `PatternBindingSyntax` — `let packs = [...]` → `packs`.
    static func bindingName(of node: ArrayExprSyntax) -> String? {
        var current: Syntax? = node.parent
        while let syntax = current {
            if let binding = syntax.as(PatternBindingSyntax.self) {
                return binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
            }
            // Stop at a declaration boundary: an array nested inside a function body has no
            // meaningful owning binding above it.
            if syntax.is(CodeBlockSyntax.self) { return nil }
            current = syntax.parent
        }
        return nil
    }

    /// Reads a name out of an expression, with a coarse kind tag used to require array elements
    /// to be uniform. Returns nil for anything that is not name-like.
    static func nameAndKind(of expr: ExprSyntax) -> (name: String, kind: String)? {
        // "state-management" — single-segment string literals only (no interpolation).
        if let literal = expr.as(StringLiteralExprSyntax.self) {
            guard literal.segments.count == 1,
                  let segment = literal.segments.first?.as(StringSegmentSyntax.self) else {
                return nil
            }
            let text = segment.content.text
            return text.isEmpty ? nil : (text, "string")
        }

        // `StateManagement(…)` / `Foo.bar(…)` — read the constructed type or callee name.
        if let call = expr.as(FunctionCallExprSyntax.self) {
            return nameAndKind(of: call.calledExpression).map { ($0.name, "reference") }
        }

        if let member = expr.as(MemberAccessExprSyntax.self) {
            // `.stateManagement` — a leading-dot case reference.
            if member.base == nil {
                return (member.declName.baseName.text, "member")
            }
            // `StateManagement.self` names the base, not the `self` member.
            if member.declName.baseName.text == "self", let base = member.base {
                return nameAndKind(of: base).map { ($0.name, "reference") }
            }
            // `Category.stateManagement` — qualified case reference.
            return (member.declName.baseName.text, "member")
        }

        // A bare type reference: `StateManagement`. Require an uppercase initial so ordinary
        // variable references are not mistaken for names.
        if let reference = expr.as(DeclReferenceExprSyntax.self) {
            let text = reference.baseName.text
            guard text.first?.isUppercase == true else { return nil }
            return (text, "reference")
        }

        return nil
    }
}
