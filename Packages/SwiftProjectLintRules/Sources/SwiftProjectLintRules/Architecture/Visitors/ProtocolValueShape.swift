import SwiftSyntax

/// Expression shapes `ProtocolClientIndex` reads the same way in every pass.
///
/// The trees are unfolded (`Parser.parse` leaves operators unresolved), so an assignment or a
/// cast is a `SequenceExprSyntax` of its operands and operators, not a folded node.
enum ProtocolValueShape {

    /// Strips what leaves a value's protocol unchanged: `try`, `await`, `!`, and parentheses.
    static func peel(_ expression: ExprSyntax) -> ExprSyntax {
        var current = expression
        while let inner = transparentInner(of: current) {
            current = inner
        }
        return current
    }

    private static func transparentInner(of expression: ExprSyntax) -> ExprSyntax? {
        if let tryExpr = expression.as(TryExprSyntax.self) {
            return tryExpr.expression
        }
        if let awaitExpr = expression.as(AwaitExprSyntax.self) {
            return awaitExpr.expression
        }
        if let unwrap = expression.as(ForceUnwrapExprSyntax.self) {
            return unwrap.expression
        }
        if let tuple = expression.as(TupleExprSyntax.self), tuple.elements.count == 1,
           let element = tuple.elements.first, element.label == nil {
            return element.expression
        }
        return nil
    }

    /// True when `parent` passes its child's value through unchanged — the inverse of `peel`,
    /// plus optional chaining (`store?.save()`), which keeps the receiver a protocol value.
    static func isTransparentWrapper(_ parent: Syntax) -> Bool {
        parent.is(TryExprSyntax.self) || parent.is(AwaitExprSyntax.self)
            || parent.is(ForceUnwrapExprSyntax.self) || parent.is(OptionalChainingExprSyntax.self)
    }

    /// The parenthesised expression `(child)`, when `child` sits alone inside parentheses.
    static func enclosingParentheses(of child: Syntax) -> TupleExprSyntax? {
        guard let element = child.parent?.as(LabeledExprSyntax.self), element.label == nil,
              let tuple = element.parent?.parent?.as(TupleExprSyntax.self),
              tuple.elements.count == 1 else {
            return nil
        }
        return tuple
    }

    /// The base name a call invokes: `make` for `make()`, `x.make()` and `Self.make()`.
    static func calleeName(of expression: ExprSyntax) -> String? {
        guard let call = expression.as(FunctionCallExprSyntax.self) else { return nil }
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        if let access = call.calledExpression.as(MemberAccessExprSyntax.self) {
            return access.declName.baseName.text
        }
        return nil
    }

    /// The target type of `x as? T`, `x as! T` or `x as T` written alone as an expression.
    static func castTarget(of expression: ExprSyntax) -> TypeSyntax? {
        guard let sequence = expression.as(SequenceExprSyntax.self) else { return nil }
        let elements = Array(sequence.elements)
        guard elements.count == 3, elements[1].is(UnresolvedAsExprSyntax.self),
              let target = elements[2].as(TypeExprSyntax.self) else {
            return nil
        }
        return target.type
    }

    /// The operands whose value a 3-element sequence passes on: both sides of `a ?? b`, both
    /// branches of `c ? a : b`. `nil` for any other sequence.
    static func valueOperands(of sequence: SequenceExprSyntax) -> [ExprSyntax]? {
        let elements = Array(sequence.elements)
        guard elements.count == 3 else { return nil }
        if let ternary = elements[1].as(UnresolvedTernaryExprSyntax.self) {
            return [ternary.thenExpression, elements[2]]
        }
        if elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text == "??" {
            return [elements[0], elements[2]]
        }
        return nil
    }

    /// The argument labels of a call: `_` for an unlabelled argument, `nil` for a trailing
    /// closure, whose parameter label the call site does not spell.
    static func labels(of call: FunctionCallExprSyntax) -> [String?] {
        var labels: [String?] = call.arguments.map { $0.label?.text ?? "_" }
        if call.trailingClosure != nil {
            labels.append(nil)
        }
        labels.append(contentsOf: call.additionalTrailingClosures.map(\.label.text))
        return labels
    }

    /// The labels a member reference is used with: spelled (`store.save(_:)`), or taken from the
    /// call it is the callee of, or `nil` when it is neither.
    static func labels(ofMember access: MemberAccessExprSyntax) -> [String?]? {
        if let spelled = access.declName.argumentNames {
            return spelled.arguments.map(\.name.text)
        }
        if let call = access.parent?.as(FunctionCallExprSyntax.self),
           call.calledExpression.id == access.id {
            return labels(of: call)
        }
        return nil
    }
}
