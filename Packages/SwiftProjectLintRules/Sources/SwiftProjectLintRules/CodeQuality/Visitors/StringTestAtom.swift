import SwiftSyntax

/// One operand of a boolean chain read as a test of a string against a literal — `x == "a"`,
/// `x.contains("a")`, `x.hasPrefix("a")`, `x.hasSuffix("a")`, `x.isEmpty`, or the negation of
/// one — so that `SubsumedConditionVisitor` can decide when one operand implies another.
///
/// Only these shapes are read, because only over these is implication decidable from the
/// literals alone: `x.contains("tag:yaml.org,2002:int")` implies `x.contains("int")` whatever
/// `x` is, since the first literal contains the second. Anything else is opaque, and an opaque
/// operand implies nothing and is implied by nothing — the analysis is sound by refusing to
/// guess.
struct StringTestAtom: Equatable {

    enum Kind: Equatable {
        case equals(String)
        case contains(String)
        case prefix(String)
        case suffix(String)
        case isEmpty
    }

    /// The tested expression, as written — `tagDescription`, `line.trimmingCharacters(in: .whitespaces)`.
    let receiver: String
    let kind: Kind
    let negated: Bool
    /// Whether the receiver is known to be a string, so that `contains` is substring containment
    /// rather than membership — see `StringReceiverEvidence`. Set by the visitor.
    var receiverIsString = false

    init(receiver: String, kind: Kind, negated: Bool) {
        self.receiver = receiver
        self.kind = kind
        self.negated = negated
    }

    var negation: Self {
        var atom = Self(receiver: receiver, kind: kind, negated: !negated)
        atom.receiverIsString = receiverIsString
        return atom
    }

    /// Only `contains` is ambiguous between a string and a collection.
    var provesString: Bool {
        if case .contains = kind { return false }
        if case .isEmpty = kind { return false }
        return true
    }

    // MARK: - Reading

    /// The atom an operand states, or `nil` when it is not one of the shapes above.
    static func read(_ elements: [ExprSyntax]) -> Self? {
        if elements.count == 1 { return read(elements[0]) }
        guard elements.count == 3,
              let comparison = elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text,
              comparison == "==" || comparison == "!=" else { return nil }
        let (receiver, literal): (ExprSyntax, String)
        if let value = literalText(elements[2]) {
            (receiver, literal) = (elements[0], value)
        } else if let value = literalText(elements[0]) {
            (receiver, literal) = (elements[2], value)
        } else {
            return nil
        }
        guard literalText(receiver) == nil else { return nil }
        let kind: Kind = literal.isEmpty ? .isEmpty : .equals(literal)
        return Self(receiver: receiver.trimmedDescription, kind: kind, negated: comparison == "!=")
    }

    private static func read(_ expr: ExprSyntax) -> Self? {
        if let prefix = expr.as(PrefixOperatorExprSyntax.self), prefix.operator.text == "!" {
            return read(prefix.expression)?.negation
        }
        if let tuple = expr.as(TupleExprSyntax.self), tuple.elements.count == 1,
           let inner = tuple.elements.first, inner.label == nil {
            if let sequence = inner.expression.as(SequenceExprSyntax.self) {
                return read(Array(sequence.elements))
            }
            return read(inner.expression)
        }
        if let member = expr.as(MemberAccessExprSyntax.self), member.declName.baseName.text == "isEmpty",
           let base = member.base {
            return Self(receiver: base.trimmedDescription, kind: .isEmpty, negated: false)
        }
        guard let call = expr.as(FunctionCallExprSyntax.self) else { return nil }
        return read(call)
    }

    /// `x.contains("a")`, `x.hasPrefix("a")`, `x.hasSuffix("a")`.
    private static func read(_ call: FunctionCallExprSyntax) -> Self? {
        guard let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              let base = member.base,
              call.arguments.count == 1, call.trailingClosure == nil,
              let argument = call.arguments.first, argument.label == nil,
              let literal = literalText(argument.expression), !literal.isEmpty else { return nil }
        let kind: Kind
        switch member.declName.baseName.text {
        case "contains": kind = .contains(literal)
        case "hasPrefix": kind = .prefix(literal)
        case "hasSuffix": kind = .suffix(literal)
        default: return nil
        }
        return Self(receiver: base.trimmedDescription, kind: kind, negated: false)
    }

    /// A string literal's text when it has no interpolation.
    private static func literalText(_ expr: ExprSyntax) -> String? {
        guard let literal = expr.as(StringLiteralExprSyntax.self) else { return nil }
        var text = ""
        for segment in literal.segments {
            guard let plain = segment.as(StringSegmentSyntax.self) else { return nil }
            text += plain.content.text
        }
        // An escape sequence would have to be decoded to compare; refuse rather than guess.
        return text.contains("\\") ? nil : text
    }

    // MARK: - Implication

    /// Whether every string satisfying `self` satisfies `other`. `false` means "not known to",
    /// never "known not to".
    func implies(_ other: Self) -> Bool {
        guard receiver == other.receiver else { return false }
        if kind == other.kind, negated == other.negated { return true }
        switch (negated, other.negated) {
        case (true, true):
            // Contrapositive: ¬p ⇒ ¬q exactly when q ⇒ p.
            return other.negation.implies(negation)

        case (true, false):
            return false

        case (false, _):
            return positiveImplies(other)
        }
    }

    /// `self` is un-negated.
    private func positiveImplies(_ other: Self) -> Bool {
        switch kind {
        case .equals(let value):
            return other.holds(for: value)

        case .isEmpty:
            return other.holds(for: "")

        case .contains(let literal):
            return containsImplies(literal, other: other)

        case .prefix(let literal):
            return Self.affixImplies(literal, other: other, isPrefix: true)

        case .suffix(let literal):
            return Self.affixImplies(literal, other: other, isPrefix: false)
        }
    }

    /// What `x.contains(literal)` implies. Substring containment needs `x` to be a string; for a
    /// collection, `contains` is membership and one element says nothing about another.
    private func containsImplies(_ literal: String, other: Self) -> Bool {
        switch (other.kind, other.negated) {
        case (.contains(let target), false): return receiverIsString && literal.contains(target)

        case (.isEmpty, true): return true

        case (.equals(let value), true): return !value.contains(literal)

        default: return false
        }
    }

    /// What `x.hasPrefix(literal)` (or `hasSuffix`) implies.
    private static func affixImplies(_ literal: String, other: Self, isPrefix: Bool) -> Bool {
        let has: (String, String) -> Bool = isPrefix ? { $0.hasPrefix($1) } : { $0.hasSuffix($1) }
        let sameAffix: String?
        switch other.kind {
        case .prefix(let target): sameAffix = isPrefix ? target : nil

        case .suffix(let target): sameAffix = isPrefix ? nil : target

        default: sameAffix = nil
        }
        if let target = sameAffix {
            // Two prefixes neither of which extends the other cannot both hold.
            return other.negated
                ? !has(literal, target) && !has(target, literal)
                : has(literal, target)
        }
        switch (other.kind, other.negated) {
        case (.contains(let target), false): return literal.contains(target)

        case (.isEmpty, true): return true

        case (.equals(let value), true): return !has(value, literal)

        default: return false
        }
    }

    /// Whether `value` satisfies this atom.
    private func holds(for value: String) -> Bool {
        let positive: Bool
        switch kind {
        case .equals(let literal): positive = value == literal
        case .contains(let literal): positive = value.contains(literal)
        case .prefix(let literal): positive = value.hasPrefix(literal)
        case .suffix(let literal): positive = value.hasSuffix(literal)
        case .isEmpty: positive = value.isEmpty
        }
        return positive != negated
    }
}
