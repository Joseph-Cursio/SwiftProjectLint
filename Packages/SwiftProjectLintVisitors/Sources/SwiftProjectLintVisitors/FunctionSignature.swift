import SwiftSyntax

/// Canonical bare-receiver function signature: base name plus the ordered list
/// of argument labels (external labels, not internal parameter names). Unlabeled
/// positional arguments are represented as `"_"`, matching Swift's own rendering
/// convention (`foo(_:bar:)`).
///
/// Two declarations share a signature iff a single call site could match either
/// without further type information. The linter has no type checker, so this is
/// the strongest disambiguator available on pure syntax.
///
/// ## Examples
/// - `func upsert(_ id: Int)` → `upsert(_:)`
/// - `func create(key: String, value: some Codable, expires: Duration?)` → `create(key:value:expires:)`
/// - `func create(key: String, value: some Codable)` → `create(key:value:)` (distinct from above)
/// - `func send(to email: String)` → `send(to:)`  — external label wins over internal name
public struct FunctionSignature: Sendable, Hashable {
    public let name: String
    public let argumentLabels: [String]

    public init(name: String, argumentLabels: [String]) {
        self.name = name
        self.argumentLabels = argumentLabels
    }

    /// Canonical textual rendering, matching Swift's documentation form:
    /// `name(label1:label2:…)`. Used in diagnostics and debug output.
    public var description: String {
        let labels = argumentLabels.map { "\($0):" }.joined()
        return "\(name)(\(labels))"
    }
}

public extension FunctionSignature {

    /// Computes the signature of a function declaration from its syntax. Uses
    /// each parameter's **external** label (Swift's `firstName`), or `"_"` when
    /// the declaration suppresses the label.
    static func from(declaration: FunctionDeclSyntax) -> FunctionSignature {
        let labels = declaration.signature.parameterClause.parameters.map { param -> String in
            // `firstName` is the external label ("_" for suppressed) or the
            // single name when the declaration uses only one name. The internal
            // `secondName`, when present, is not part of the call-site signature.
            let firstText = param.firstName.text
            return firstText.isEmpty ? "_" : firstText
        }
        return FunctionSignature(name: declaration.name.text, argumentLabels: labels)
    }

    /// Computes the signature of a call site from its syntax. Each argument's
    /// external label is read from `LabeledExprSyntax.label`; unlabeled positional
    /// arguments become `"_"`. Trailing closures are counted as a single
    /// argument (matching how Swift encodes the call). Returns `nil` when the
    /// callee expression is not a plain identifier or member access that the
    /// Phase-1 linter can resolve.
    static func from(call: FunctionCallExprSyntax) -> FunctionSignature? {
        guard let name = calleeBaseName(of: call.calledExpression) else { return nil }

        var labels: [String] = call.arguments.map { arg in
            arg.label?.text ?? "_"
        }
        // Trailing closures are passed without a label in the `arguments`
        // clause; they appear separately on `FunctionCallExprSyntax`. Treat the
        // first trailing closure as a single unlabeled argument and additional
        // trailing closures as labeled by their own `label` token. This matches
        // the Swift compiler's own call-signature encoding.
        if call.trailingClosure != nil {
            labels.append("_")
        }
        for additional in call.additionalTrailingClosures {
            labels.append(additional.label.text)
        }

        return FunctionSignature(name: name, argumentLabels: labels)
    }

    private static func calleeBaseName(of expr: ExprSyntax) -> String? {
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }
}
