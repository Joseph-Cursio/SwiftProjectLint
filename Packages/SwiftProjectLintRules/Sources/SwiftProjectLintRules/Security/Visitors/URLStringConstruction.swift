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
    /// when the text is fixed. When more than one part of it builds text, the first names it.
    init?(_ expression: ExprSyntax) {
        guard let construction = Self.construction(of: expression) else { return nil }
        self = construction
    }

    // MARK: - The parts that become the URL's text

    /// How the text of `expression` is built, read only where its value becomes that text: the
    /// whole of it, each side of a `??`, each branch of a `?:`, and inside parentheses.
    ///
    /// Anything else in the argument computes a value the text is chosen *by*, not made *of*. In
    /// `index + 1 < count ? next : "https://example.com/end"` the `+` is arithmetic in the
    /// ternary's condition, and in `pages[index + 1]` or `path(for: page + 1)` it belongs to a
    /// subscript or a call — none of them is concatenation.
    private static func construction(of expression: ExprSyntax) -> Self? {
        let expression = withoutParentheses(expression)
        if let literal = expression.as(StringLiteralExprSyntax.self) {
            return isInterpolated(literal) ? .interpolation : nil
        }
        if let sequence = expression.as(SequenceExprSyntax.self) {
            return construction(ofSequence: Array(sequence.elements))
        }
        // The folded spellings, the shape once an `OperatorTable` has run over the tree.
        if let ternary = expression.as(TernaryExprSyntax.self) {
            return construction(of: ternary.thenExpression) ?? construction(of: ternary.elseExpression)
        }
        if let cast = expression.as(AsExprSyntax.self) {
            return construction(of: cast.expression)
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self) {
            if isNilCoalescing(infix.operator) {
                return construction(of: infix.leftOperand) ?? construction(of: infix.rightOperand)
            }
            if isPlus(infix.operator) {
                return concatenation(of: [infix.leftOperand, infix.rightOperand])
            }
        }
        return nil
    }

    /// How an unfolded sequence builds its text. `SwiftParser` does not fold operators, so
    /// `fallback ?? base + "/" + path` arrives as one flat `SequenceExprSyntax` — operands at even
    /// positions, operators at odd ones. The rule settles only the two precedences that decide
    /// which operands are text: those of `?:` and `??`, the loosest a `String` is built with.
    private static func construction(ofSequence elements: [ExprSyntax]) -> Self? {
        // `?:` binds loosest and groups to the right, so the first one splits the sequence: what
        // precedes it is its condition, and what follows it is its `else` branch.
        if let index = elements.firstIndex(where: { $0.is(UnresolvedTernaryExprSyntax.self) }),
           let ternary = elements[index].as(UnresolvedTernaryExprSyntax.self) {
            return construction(of: ternary.thenExpression)
                ?? construction(ofSequence: Array(elements[(index + 1)...]))
        }
        // Below `?:`, a `??` binds looser than `+` and a cast. Any other operator — a comparison,
        // `&&`, `-` — makes a value that is not a `String`, so nothing in it is the URL's text.
        guard operators(of: elements).allSatisfy(isStringOperator) else { return nil }
        return sides(of: elements).lazy.compactMap(construction(ofSide:)).first
    }

    /// `elements` cut at each `??`: `[a, ??, b, +, c]` is `[a]` and `[b, +, c]`. A sequence with no
    /// `??` is one side.
    private static func sides(of elements: [ExprSyntax]) -> [[ExprSyntax]] {
        var sides: [[ExprSyntax]] = [[]]
        for (offset, element) in elements.enumerated() {
            if offset.isMultiple(of: 2) == false, isNilCoalescing(element) {
                sides.append([])
            } else {
                sides[sides.count - 1].append(element)
            }
        }
        return sides
    }

    /// How one side of a `??` builds its text: a lone operand is read as a whole expression, so a
    /// parenthesised one is opened; a chain of `+` is concatenation. A cast is read through first,
    /// so `base + path as String` and `(base + path) as String` are concatenations, and
    /// `value as? String` is whatever `value` is.
    private static func construction(ofSide side: [ExprSyntax]) -> Self? {
        let side = withoutCasts(side)
        if side.count == 1 { return construction(of: side[0]) }
        guard operators(of: side).allSatisfy(isPlus) else { return nil }
        return concatenation(of: operands(of: side))
    }

    /// `elements` with each cast dropped. A cast binds tighter than `+` and `??`, so `as String`
    /// applies to the operand just before it, and that operand's text is the text the cast gives:
    /// `[base, +, path, as, String]` is `[base, +, path]`. The parser spells a cast as an `as`
    /// in an operator position followed by its type in the next operand position.
    private static func withoutCasts(_ elements: [ExprSyntax]) -> [ExprSyntax] {
        var kept: [ExprSyntax] = []
        var index = 0
        while index < elements.count {
            if index.isMultiple(of: 2) == false, elements[index].is(UnresolvedAsExprSyntax.self) {
                index += 2
                continue
            }
            kept.append(elements[index])
            index += 1
        }
        return kept
    }

    // MARK: - Concatenation

    /// `.concatenation` for strings joined with `+`, unless every one of them is a plain literal:
    /// `"https://example.com/" + "v2/users"` is one constant split across lines, with nothing to
    /// encode. A `+` read here is never arithmetic: its result is the argument's text, or a side
    /// of a `??` or a branch of a `?:` that is.
    private static func concatenation(of operands: [ExprSyntax]) -> Self? {
        joinedOperands(operands).allSatisfy(isFixedLiteral) ? nil : .concatenation
    }

    /// `operands` with every one that is itself a `+`-only chain — parenthesised, or nested by
    /// folding — spliced in its place, so the literals of `"a" + ("b" + "c")` are all counted.
    private static func joinedOperands(_ operands: [ExprSyntax]) -> [ExprSyntax] {
        operands.flatMap { operand -> [ExprSyntax] in
            let operand = withoutParentheses(operand)
            if let infix = operand.as(InfixOperatorExprSyntax.self), isPlus(infix.operator) {
                return joinedOperands([infix.leftOperand, infix.rightOperand])
            }
            if let cast = operand.as(AsExprSyntax.self) {
                return joinedOperands([cast.expression])
            }
            if let sequence = operand.as(SequenceExprSyntax.self) {
                let elements = withoutCasts(Array(sequence.elements))
                if elements.count == 1 { return joinedOperands(elements) }
                if operators(of: elements).allSatisfy(isPlus) {
                    return joinedOperands(Self.operands(of: elements))
                }
            }
            return [operand]
        }
    }

    // MARK: - Operators

    private static func operands(of elements: [ExprSyntax]) -> [ExprSyntax] {
        stride(from: 0, to: elements.count, by: 2).map { elements[$0] }
    }

    /// The operator positions of an unfolded sequence. A ternary's `? then :` and a cast's `as`
    /// hold one too.
    private static func operators(of elements: [ExprSyntax]) -> [ExprSyntax] {
        stride(from: 1, to: elements.count, by: 2).map { elements[$0] }
    }

    /// `+`, `??`, or a cast — the operators a `String` value can be built with below `?:`.
    private static func isStringOperator(_ operatorExpression: ExprSyntax) -> Bool {
        isPlus(operatorExpression) || isNilCoalescing(operatorExpression)
            || operatorExpression.is(UnresolvedAsExprSyntax.self)
    }

    private static func isPlus(_ operatorExpression: ExprSyntax) -> Bool {
        operatorExpression.as(BinaryOperatorExprSyntax.self)?.operator.text == "+"
    }

    private static func isNilCoalescing(_ operatorExpression: ExprSyntax) -> Bool {
        operatorExpression.as(BinaryOperatorExprSyntax.self)?.operator.text == "??"
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
