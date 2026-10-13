import SwiftSyntax

/// Whether an index is a loop's variable running over every position: `rows[index]` inside
/// `for index in rows.indices`, `for index in 0..<rows.count`,
/// `for (index, expected) in names.enumerated()` or `rows.indices.forEach { index in … }`. Such a
/// loop compares the whole sequence in order rather than picking one view.
///
/// The key has to be that loop's own variable, and the loop unfiltered — no `where`, and no
/// `if index == 1`, `guard index == 1` or `switch index` around the use — and a range has to run to
/// a count: `0..<3` picks three views.
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

    /// `expected.enumerated()` or `zip(rows.indices, expected)`: pairs whose first element is every
    /// position.
    private static func pairsEveryPosition(_ sequence: ExprSyntax, _ resolver: InspectionBindingResolver) -> Bool {
        guard let call = InspectionChainEvaluator.unwrapped(sequence).as(FunctionCallExprSyntax.self) else {
            return false
        }
        if call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "enumerated" {
            return call.arguments.isEmpty
        }
        let isZip = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "zip"
        return isZip && call.arguments.first.map { coversEveryPosition($0.expression, resolver) } == true
    }

    /// `rows.indices`, `rows.indices.reversed()`, `0..<rows.count`, `0 ..< rows.endIndex`,
    /// `rows.startIndex..<rows.endIndex`, `0...rows.count - 1`, `0..<min(rows.count, expected.count)`
    /// or `0..<count` with `let count = rows.count`, in parentheses or not.
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
        let upper = Array(elements.dropFirst(2))
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

    /// Between the use and the loop: `if index == 1 { … }`, `guard index == 1 else { continue }`
    /// before the use, or a `case` of `switch index` — each reaches one position after all.
    private static func narrowsToOnePosition(_ reference: DeclReferenceExprSyntax, below scope: Syntax) -> Bool {
        let name = reference.baseName.text
        var child = Syntax(reference)
        while let parent = child.parent, parent.id != scope.id {
            if let ifExpr = parent.as(IfExprSyntax.self), child.id == ifExpr.body.id,
               comparesEquality(of: name, in: ifExpr.conditions) {
                return true
            }
            if let switchCase = parent.as(SwitchCaseSyntax.self), case .case = switchCase.label,
               let switchExpr = switchCase.parent?.parent?.as(SwitchExprSyntax.self),
               InspectionChainEvaluator.unwrapped(switchExpr.subject).as(DeclReferenceExprSyntax.self)?
                .baseName.text == name {
                return true
            }
            if let items = parent.as(CodeBlockItemListSyntax.self), guardsEquality(of: name, in: items, before: child) {
                return true
            }
            child = parent
        }
        return false
    }

    private static func guardsEquality(
        of name: String,
        in items: CodeBlockItemListSyntax,
        before child: Syntax
    ) -> Bool {
        items.contains { item in
            guard item.position < child.position, let guardStmt = item.item.as(GuardStmtSyntax.self) else {
                return false
            }
            return comparesEquality(of: name, in: guardStmt.conditions)
        }
    }

    /// `index == 1`, `1 == index` or `index == last || …`: the key itself, compared with `==`.
    private static func comparesEquality(of name: String, in conditions: ConditionElementListSyntax) -> Bool {
        conditions.contains { element in
            guard case .expression(let expr) = element.condition,
                  let elements = expr.as(SequenceExprSyntax.self).map({ Array($0.elements) }) else {
                return false
            }
            return elements.indices.contains { index in
                guard elements[index].as(BinaryOperatorExprSyntax.self)?.operator.text == "==" else { return false }
                return [index - 1, index + 1].contains { side in
                    elements.indices.contains(side)
                        && elements[side].as(DeclReferenceExprSyntax.self)?.baseName.text == name
                }
            }
        }
    }
}
