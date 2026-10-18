import SwiftSyntax

/// Whether an index is a loop's variable running over every position: `rows[index]` inside
/// `for index in rows.indices`, `for index in 0..<rows.count`,
/// `for (index, expected) in names.enumerated()` or `rows.indices.forEach { index in … }`. Such a
/// loop compares the whole sequence in order rather than picking one view.
///
/// The key has to be that loop's own variable, and the loop unfiltered — no `where`, no
/// `if index == 1`, `if case 1 = index`, `guard index > 0` or `switch index` around the use, and no
/// `if index == 0 { continue }` before it — and a range has to run to a count: `0..<3` picks three
/// views.
enum LoopPositions {

    static func isLoopOverEveryPosition(_ key: ExprSyntax, resolver: InspectionBindingResolver, depth: Int = 0) -> Bool {
        guard depth < 4, let reference = InspectionChainEvaluator.unwrapped(key).as(DeclReferenceExprSyntax.self),
              let resolved = resolver.resolveWithScope(reference.baseName.text, from: Syntax(reference)),
              narrowsToOnePosition(reference, below: resolved.scope) == false else {
            return false
        }
        let name = reference.baseName.text
        if let loop = resolved.scope.as(ForStmtSyntax.self) {
            guard loop.whereClause == nil else { return false }
            return visitsEveryPosition(name, boundBy: loop.pattern, from: loop.sequence, resolver)
        }
        guard let closure = resolved.scope.as(ClosureExprSyntax.self) else { return false }
        // `[index = index]` captures the loop's variable.
        if case .value(let captured, _) = resolved.binding, captured.is(DeclReferenceExprSyntax.self) {
            return isLoopOverEveryPosition(captured, resolver: resolver, depth: depth + 1)
        }
        return visitsEveryPosition(name, parameterOf: closure, resolver)
    }

    /// `rows.indices.forEach { index in … }`, `expected.enumerated().forEach { index, name in … }`.
    private static func visitsEveryPosition(
        _ name: String,
        parameterOf closure: ClosureExprSyntax,
        _ resolver: InspectionBindingResolver
    ) -> Bool {
        guard let call = InspectionRelay.enclosingCall(of: closure),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              everyElementMethods.contains(member.declName.baseName.text),
              let sequence = member.base else {
            return false
        }
        let parameters = InspectionBindingResolver.closureParameters(closure).map(\.name)
        if parameters.count <= 1 {
            return (parameters.first ?? "$0") == name && coversEveryPosition(sequence, resolver)
        }
        return parameters.first == name && pairsEveryPosition(sequence, resolver)
    }

    private static let everyElementMethods: Set<String> = ["forEach", "map", "compactMap", "flatMap", "allSatisfy"]

    /// `index` alone over a range or `indices`, or first in a tuple over `enumerated()` or
    /// `zip(rows.indices, expected)`.
    private static func visitsEveryPosition(
        _ name: String,
        boundBy pattern: PatternSyntax,
        from sequence: ExprSyntax,
        _ resolver: InspectionBindingResolver
    ) -> Bool {
        if InspectionBindingResolver.identifier(of: pattern) == name {
            return coversEveryPosition(sequence, resolver)
        }
        guard let tuple = pattern.as(TuplePatternSyntax.self),
              tuple.elements.first.flatMap({ InspectionBindingResolver.identifier(of: $0.pattern) }) == name else {
            return false
        }
        return pairsEveryPosition(sequence, resolver)
    }

    /// `expected.enumerated()`, `zip(rows.indices, expected)` or `zip(0..., expected)`: pairs whose
    /// first element is every position.
    private static func pairsEveryPosition(_ sequence: ExprSyntax, _ resolver: InspectionBindingResolver) -> Bool {
        guard let call = InspectionChainEvaluator.unwrapped(sequence).as(FunctionCallExprSyntax.self) else {
            return false
        }
        if call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "enumerated" {
            return call.arguments.isEmpty
        }
        guard call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "zip",
              let first = call.arguments.first.map({ InspectionChainEvaluator.unwrapped($0.expression) }) else {
            return false
        }
        if let open = first.as(PostfixOperatorExprSyntax.self), open.operator.text == "..." {
            return isFirstPosition(InspectionChainEvaluator.unwrapped(open.expression))
        }
        return coversEveryPosition(first, resolver)
    }

    /// `rows.indices`, `rows.indices.reversed()`, `0..<rows.count`, `0 ..< rows.endIndex`,
    /// `rows.startIndex..<rows.endIndex`, `0...rows.count - 1`, `0...(rows.count - 1)`,
    /// `0..<min(rows.count, expected.count)` or `0..<count` with `let count = rows.count`, in
    /// parentheses or not.
    static func coversEveryPosition(_ sequence: ExprSyntax, _ resolver: InspectionBindingResolver) -> Bool {
        let sequence = InspectionChainEvaluator.unwrapped(sequence)
        if let call = sequence.as(FunctionCallExprSyntax.self), call.arguments.isEmpty,
           let reversed = call.calledExpression.as(MemberAccessExprSyntax.self),
           reversed.declName.baseName.text == "reversed", let base = reversed.base {
            return coversEveryPosition(base, resolver)
        }
        if sequence.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "indices" {
            return true
        }
        guard let elements = sequence.as(SequenceExprSyntax.self).map({ Array($0.elements) }), elements.count >= 3,
              isFirstPosition(elements[0]),
              let range = elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text else {
            return false
        }
        var upper = Array(elements.dropFirst(2))
        if upper.count == 1, let inner = InspectionChainEvaluator.unwrapped(upper[0]).as(SequenceExprSyntax.self) {
            upper = Array(inner.elements)
        }
        switch range {
        case "..<":
            return upper.count == 1 && isCount(upper[0], resolver)

        case "...":
            return upper.count == 3 && isCount(upper[0], resolver)
                && upper[1].trimmedDescription == "-" && upper[2].trimmedDescription == "1"

        default:
            return false
        }
    }

    /// `0` or `rows.startIndex`.
    private static func isFirstPosition(_ expr: ExprSyntax) -> Bool {
        expr.as(IntegerLiteralExprSyntax.self)?.literal.text == "0"
            || expr.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "startIndex"
    }

    /// `rows.count`, `rows.endIndex`, `min(rows.count, expected.count)`, or a name bound to one.
    private static func isCount(_ expr: ExprSyntax, _ resolver: InspectionBindingResolver, depth: Int = 0) -> Bool {
        let expr = InspectionChainEvaluator.unwrapped(expr)
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return ["count", "endIndex"].contains(member.declName.baseName.text)
        }
        if let call = expr.as(FunctionCallExprSyntax.self),
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "min" {
            return call.arguments.isEmpty == false && call.arguments.allSatisfy { isCount($0.expression, resolver) }
        }
        guard depth < 4, let reference = expr.as(DeclReferenceExprSyntax.self),
              case .value(let value, _) = resolver.resolve(reference.baseName.text, from: Syntax(reference)) else {
            return false
        }
        return isCount(value, resolver, depth: depth + 1)
    }

    // MARK: - Narrowing

    /// Between the use and the loop: `if index == 1 { … }` (or its `else`), `if case 1 = index`,
    /// `guard index > 0 else { continue }` or `if index == 0 { continue }` before the use, or a
    /// `case` of `switch index` — each skips or picks positions, as a `where` would.
    private static func narrowsToOnePosition(_ reference: DeclReferenceExprSyntax, below scope: Syntax) -> Bool {
        let name = reference.baseName.text
        var child = Syntax(reference)
        while let parent = child.parent, parent.id != scope.id {
            if let ifExpr = parent.as(IfExprSyntax.self),
               child.id == ifExpr.body.id || child.id == ifExpr.elseBody.map(Syntax.init)?.id,
               comparesPosition(of: name, in: ifExpr.conditions) {
                return true
            }
            if let switchCase = parent.as(SwitchCaseSyntax.self), case .case = switchCase.label,
               let switchExpr = switchCase.parent?.parent?.as(SwitchExprSyntax.self),
               InspectionChainEvaluator.unwrapped(switchExpr.subject).as(DeclReferenceExprSyntax.self)?
                .baseName.text == name {
                return true
            }
            if let items = parent.as(CodeBlockItemListSyntax.self),
               filtersPosition(of: name, in: items, before: child) {
                return true
            }
            child = parent
        }
        return false
    }

    /// A `guard` on the key, or an `if` on it whose body leaves the iteration, before the use.
    private static func filtersPosition(
        of name: String,
        in items: CodeBlockItemListSyntax,
        before child: Syntax
    ) -> Bool {
        items.contains { item in
            guard item.position < child.position else { return false }
            if let guardStmt = item.item.as(GuardStmtSyntax.self) {
                return comparesPosition(of: name, in: guardStmt.conditions)
            }
            let ifExpr = item.item.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self)
                ?? item.item.as(IfExprSyntax.self)
            guard let ifExpr, leavesIteration(ifExpr.body) else { return false }
            return comparesPosition(of: name, in: ifExpr.conditions)
        }
    }

    /// `{ continue }`, `{ break }`, `{ return }`, `{ throw … }`.
    private static func leavesIteration(_ body: CodeBlockSyntax) -> Bool {
        guard let last = body.statements.last?.item else { return false }
        return last.is(ContinueStmtSyntax.self) || last.is(BreakStmtSyntax.self)
            || last.is(ReturnStmtSyntax.self) || last.is(ThrowStmtSyntax.self)
    }

    /// `index == 1`, `(index == 1)`, `index > 0 && flag`, `index + 1 == count` or `case 1 = index`:
    /// the key itself, compared. `expected[index] == "b"` compares the data, not the position.
    private static func comparesPosition(of name: String, in conditions: ConditionElementListSyntax) -> Bool {
        conditions.contains { element in
            switch element.condition {
            case .expression(let expr):
                return comparesPosition(of: name, in: expr)

            case .matchingPattern(let match):
                return isKey(name, match.initializer.value)

            default:
                return false
            }
        }
    }

    private static func comparesPosition(of name: String, in expr: ExprSyntax, depth: Int = 0) -> Bool {
        guard depth < 8 else { return false }
        let expr = InspectionChainEvaluator.unwrapped(expr)
        if let negated = expr.as(PrefixOperatorExprSyntax.self) {
            return comparesPosition(of: name, in: negated.expression, depth: depth + 1)
        }
        guard let elements = expr.as(SequenceExprSyntax.self)?.elements else { return false }
        // Split at `&&` and `||`: each clause is one comparison, or a parenthesised condition.
        var clause: [ExprSyntax] = []
        for element in elements.map(Optional.some) + [nil] {
            let separator = element?.as(BinaryOperatorExprSyntax.self).map { ["&&", "||"].contains($0.operator.text) }
            if let element, separator != true {
                clause.append(element)
                continue
            }
            if clause.count == 1, comparesPosition(of: name, in: clause[0], depth: depth + 1) {
                return true
            }
            let compares = clause.contains {
                comparisonOperators.contains($0.as(BinaryOperatorExprSyntax.self)?.operator.text ?? "")
            }
            if compares, clause.contains(where: { isKey(name, $0) }) {
                return true
            }
            clause = []
        }
        return false
    }

    private static let comparisonOperators: Set<String> = ["==", "!=", "<", "<=", ">", ">=", "~="]

    private static func isKey(_ name: String, _ expr: ExprSyntax) -> Bool {
        InspectionChainEvaluator.unwrapped(expr).as(DeclReferenceExprSyntax.self)?.baseName.text == name
    }
}
