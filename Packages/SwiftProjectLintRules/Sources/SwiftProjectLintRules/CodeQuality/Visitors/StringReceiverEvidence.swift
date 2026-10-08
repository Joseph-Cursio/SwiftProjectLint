import SwiftSyntax

/// Whether an expression is known to be a **string**, as `SubsumedConditionVisitor` needs before
/// it reads `contains` as substring containment.
///
/// `x.contains("ab")` implies `x.contains("a")` only for a string. For an array or a set,
/// `contains` is membership, and `modifiers.contains("fileprivate") || modifiers.contains("private")`
/// tests two independent elements. Before this check that was the rule's one false-positive
/// class: 9 of 47 findings over 55 repositories, every one a collection of modifier, conformance
/// or path-component names.
///
/// Evidence is syntactic, and its absence silences the finding rather than guessing:
/// - the expression ends in a string-producing call or property — `.trimmingCharacters(in:)`,
///   `.lowercased()`, `.description`;
/// - or it is a name declared in the enclosing declaration as a `String` or `Substring`
///   parameter, a local annotated so, a local initialised from a string literal or a
///   string-producing call, or an `as? String` binding.
///
/// `hasPrefix`, `hasSuffix` and `== "literal"` need none of this: they exist only on strings,
/// so the chain itself is the evidence.
enum StringReceiverEvidence {

    private static let producingSuffixes = [
        ".description", ".trimmedDescription", ".lowercased()", ".uppercased()", ".capitalized",
        ".localizedLowercase", ".localizedUppercase"
    ]

    private static let producingCalls = [
        ".trimmingCharacters(", ".replacingOccurrences(", ".joined(", ".appending(",
        ".padding(", ".applyingTransform("
    ]

    static func isString(_ receiver: String, at node: Syntax) -> Bool {
        if producesString(receiver) { return true }
        guard receiver.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
              let scope = enclosingDeclaration(of: node) else { return false }
        return declaresString(receiver, in: scope)
    }

    private static func producesString(_ text: String) -> Bool {
        if producingSuffixes.contains(where: text.hasSuffix) { return true }
        if text.hasPrefix("String(") || text.hasPrefix("\"") { return true }
        return producingCalls.contains { text.contains($0) } && text.hasSuffix(")")
    }

    private static func isStringType(_ type: TypeSyntax?) -> Bool {
        guard let text = type?.trimmedDescription else { return false }
        return ["String", "Substring", "String?", "Substring?"].contains(text)
    }

    private static func enclosingDeclaration(of node: Syntax) -> Syntax? {
        var current = node.parent
        var found: Syntax?
        while let syntax = current {
            if syntax.is(FunctionDeclSyntax.self) || syntax.is(InitializerDeclSyntax.self)
                || syntax.is(AccessorDeclSyntax.self) || syntax.is(PatternBindingSyntax.self) {
                found = syntax
            }
            if syntax.is(MemberBlockSyntax.self) || syntax.is(SourceFileSyntax.self) { break }
            current = syntax.parent
        }
        return found
    }

    private static func declaresString(_ name: String, in scope: Syntax) -> Bool {
        if let parameter = scope.as(FunctionParameterSyntax.self),
           (parameter.secondName ?? parameter.firstName).text == name {
            return isStringType(parameter.type)
        }
        if let binding = scope.as(PatternBindingSyntax.self),
           binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name {
            if isStringType(binding.typeAnnotation?.type) { return true }
            if let value = binding.initializer?.value { return isStringValue(value) }
        }
        if let binding = scope.as(OptionalBindingConditionSyntax.self),
           binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name {
            if isStringType(binding.typeAnnotation?.type) { return true }
            if let value = binding.initializer?.value { return isStringValue(value) }
        }
        return scope.children(viewMode: .sourceAccurate).contains { declaresString(name, in: $0) }
    }

    private static func isStringValue(_ value: ExprSyntax) -> Bool {
        if value.is(StringLiteralExprSyntax.self) { return true }
        if let cast = value.as(AsExprSyntax.self) { return isStringType(cast.type) }
        if let sequence = value.as(SequenceExprSyntax.self), let last = sequence.elements.last,
           sequence.elements.count >= 3,
           sequence.elements.dropFirst().first?.is(UnresolvedAsExprSyntax.self) == true {
            return isStringType(last.as(TypeExprSyntax.self)?.type)
        }
        return producesString(value.trimmedDescription)
    }
}
