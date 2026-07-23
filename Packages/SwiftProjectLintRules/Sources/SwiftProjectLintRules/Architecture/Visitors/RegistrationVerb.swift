import SwiftSyntax

/// The shared vocabulary of "add one item to a collection / registry" method names,
/// and the callee-shape helpers built on it.
///
/// Two Architecture rules key off the same notion of a registration call:
/// `ManualRegistrationList` (single-file — flags the hand-maintained *shape*) and
/// `ParallelListDrift` (cross-file — flags a hand-maintained list that has *drifted*
/// from its counterpart). Keeping one copy of the verb list means a verb added for one
/// rule is immediately honoured by the other.
enum RegistrationVerb {

    /// Verbs meaning "add one item to a collection / registry". A run of calls to the
    /// same such method is a hand-maintained list. `#expect` / `assert` and other
    /// non-registration calls are excluded by construction.
    static let all = [
        "register", "add", "append", "insert", "put", "record",
        "bind", "connect", "install", "mount", "wire", "enroll"
    ]

    /// The subset of `all` that is *collection building* rather than unambiguous
    /// registration. `lines.append("…")` and `parts.insert("…")` overwhelmingly construct
    /// output text, so when such a call's argument is string content it is not treated as a
    /// registration call (see `isStringOutputBuilding`). The unambiguous verbs
    /// (`register`/`bind`/`connect`/…) always count, so a register-by-name registry
    /// (`commands.register("build")`) is still detected.
    static let collectionVerbs = ["append", "insert", "put"]

    /// A name matches a verb only at a camelCase boundary: `register` /
    /// `registerFactory` match `register`, but `address` does not match `add`.
    static func matches(_ name: String) -> Bool {
        matches(name, in: all)
    }

    /// Boundary match of `name` against an explicit verb list.
    static func matches(_ name: String, in verbs: [String]) -> Bool {
        let lowered = name.lowercased()
        return verbs.contains { verb in
            if lowered == verb { return true }
            guard lowered.hasPrefix(verb) else { return false }
            let boundary = name.index(name.startIndex, offsetBy: verb.count)
            return name[boundary].isUppercase
        }
    }

    /// Whether `call` is a collection verb applied to string text — the output-building shape
    /// (`lines.append("…")`, `out.append("\(x)")`), not the registration of a distinct item.
    /// String interpolation is a `StringLiteralExprSyntax`, so both literals and interpolated
    /// text are recognised.
    static func isStringOutputBuilding(_ call: FunctionCallExprSyntax) -> Bool {
        guard matches(baseName(of: call.calledExpression), in: collectionVerbs),
              let firstArgument = call.arguments.first?.expression else {
            return false
        }
        return firstArgument.is(StringLiteralExprSyntax.self)
    }

    /// The trailing identifier of a callee: `a.b.register` → `register`,
    /// `register` → `register`.
    static func baseName(of callee: ExprSyntax) -> String {
        if let member = callee.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        if let reference = callee.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        return ""
    }

    /// The callee text of `item` when it is an expression statement calling a
    /// registration-verb method; `nil` otherwise. The returned string is the full
    /// callee spelling (`SourcePatternRegistry.registerFactory`), so callers can
    /// require a run to target the *same* callee.
    static func callee(of item: CodeBlockItemSyntax) -> String? {
        guard let call = call(in: item) else { return nil }
        return call.calledExpression.trimmedDescription
    }

    /// The registration `FunctionCallExprSyntax` of `item`, or `nil` when `item` is not
    /// an expression statement calling a registration-verb method.
    static func call(in item: CodeBlockItemSyntax) -> FunctionCallExprSyntax? {
        guard case .expr(let expr) = item.item,
              let call = expr.as(FunctionCallExprSyntax.self),
              matches(baseName(of: call.calledExpression)) else {
            return nil
        }
        return call
    }
}
