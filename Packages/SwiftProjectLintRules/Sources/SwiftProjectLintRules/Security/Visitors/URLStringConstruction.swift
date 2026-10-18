import SwiftSyntax

/// How the text handed to `URL(string:)` is assembled at run time — the two shapes the Unsafe URL
/// rule reports. Read off the syntax tree, never off the source text.
///
/// The rule used to search a literal argument's source for `\(` and `+`, and only when the
/// argument *was* a literal. Both halves were wrong. `"tel:+15551234567"` and `"…?q=swift+ui"` are
/// constants whose `+` is a character of the URL, and were reported as interpolation. And
/// `base + path` is a `SequenceExprSyntax`, not a literal, so the concatenation the `+` search was
/// written for was never looked at.
enum URLStringConstruction {
    /// A literal with an `\(…)` segment: `"https://example.com/api?token=\(token)"`.
    case interpolation
    /// Strings joined with `+`: `base + path`, `"https://example.com/api?q=" + query`.
    case concatenation

    /// What the finding's message calls it.
    var phrase: String {
        switch self {
        case .interpolation: "string interpolation"
        case .concatenation: "string concatenation"
        }
    }

    /// How `expression`, the `string:` argument of a `URL(...)` call, builds its text, or `nil`
    /// when the text is fixed.
    init?(_ expression: ExprSyntax) {
        let expression = Self.withoutParentheses(expression)
        if let literal = expression.as(StringLiteralExprSyntax.self), Self.isInterpolated(literal) {
            self = .interpolation
        } else if Self.isStringConcatenation(expression) {
            self = .concatenation
        } else {
            return nil
        }
    }

    // MARK: - Concatenation

    /// Whether `expression` joins strings with `+`.
    ///
    /// `SwiftParser` does not fold operators, so `base + "/" + path` arrives as one flat
    /// `SequenceExprSyntax` — `[base, +, "/", +, path]` — and a parenthesised operand as a
    /// `TupleExprSyntax` holding another. A folded `InfixOperatorExprSyntax` — the shape once an
    /// `OperatorTable` has run over the tree — is read as a chain of two operands.
    ///
    /// A `+` is concatenation, not arithmetic, on either of two pieces of evidence:
    ///
    /// - **Every operator is `+`.** The chain is then the whole argument, and the argument is the
    ///   `String` that `URL(string:)` takes — so `base + path` is text although nothing in it is
    ///   a literal.
    /// - **An operand is a string literal.** This is what a mixed expression needs: in
    ///   `index + 1 < count ? next : last` the `+` is arithmetic in a ternary's condition, and no
    ///   operand of it is text.
    ///
    /// A chain whose every operand is a plain literal is not reported: `"https://example.com/" +
    /// "v2/users"` is one constant split across lines, with nothing to encode. Only the argument's
    /// own operators are read — the `+` in `pages[index + 1]` or `path(for: page + 1)` belongs to a
    /// subscript or a call, and is never seen.
    private static func isStringConcatenation(_ expression: ExprSyntax) -> Bool {
        guard let chain = OperatorChain(expression),
              chain.operators.contains(where: isPlus) else { return false }
        let operands = joinedOperands(of: chain)
        if operands.allSatisfy(isFixedLiteral) { return false }
        return chain.operators.allSatisfy(isPlus) || operands.contains { $0.is(StringLiteralExprSyntax.self) }
    }

    /// The chain's operands, with every operand that is itself a `+`-only chain — parenthesised,
    /// or nested by folding — spliced in its place, so a literal inside `base + ("/" + path)`
    /// counts as one of the outer chain's.
    private static func joinedOperands(of chain: OperatorChain) -> [ExprSyntax] {
        chain.operands.flatMap { operand -> [ExprSyntax] in
            let operand = withoutParentheses(operand)
            if let inner = OperatorChain(operand), inner.operators.allSatisfy(isPlus) {
                return joinedOperands(of: inner)
            }
            return [operand]
        }
    }

    private static func isPlus(_ operatorExpression: ExprSyntax) -> Bool {
        operatorExpression.as(BinaryOperatorExprSyntax.self)?.operator.text == "+"
    }

    // MARK: - Literals

    /// Whether the literal has an `\(…)` segment — read off its segments, so a `+` or a `\(` that
    /// is a character of the text (`"tel:+1…"`, `#"\(x)"#`) is not one.
    private static func isInterpolated(_ literal: StringLiteralExprSyntax) -> Bool {
        literal.segments.contains { $0.is(ExpressionSegmentSyntax.self) }
    }

    private static func isFixedLiteral(_ expression: ExprSyntax) -> Bool {
        guard let literal = expression.as(StringLiteralExprSyntax.self) else { return false }
        return isInterpolated(literal) == false
    }

    /// `expression` with any number of enclosing parentheses removed: `(("a"))` is `"a"`. A
    /// one-element tuple without a label is how the parser spells a parenthesised expression.
    private static func withoutParentheses(_ expression: ExprSyntax) -> ExprSyntax {
        var current = expression
        while let tuple = current.as(TupleExprSyntax.self),
              tuple.elements.count == 1,
              let only = tuple.elements.first,
              only.label == nil {
            current = only.expression
        }
        return current
    }
}

/// An expression's top-level operators and the operands between them, in either spelling.
///
/// An unfolded `SequenceExprSyntax` alternates operand and operator, so its operands sit at even
/// positions. A ternary's `? then :` and a cast's `as` take an operator position too, which is
/// what makes them count against a chain being `+` only.
private struct OperatorChain {
    let operands: [ExprSyntax]
    let operators: [ExprSyntax]

    init?(_ expression: ExprSyntax) {
        if let folded = expression.as(InfixOperatorExprSyntax.self) {
            operands = [folded.leftOperand, folded.rightOperand]
            operators = [folded.operator]
            return
        }
        guard let sequence = expression.as(SequenceExprSyntax.self) else { return nil }
        let elements = Array(sequence.elements)
        operands = elements.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
        operators = elements.enumerated().filter { $0.offset.isMultiple(of: 2) == false }.map(\.element)
    }
}
