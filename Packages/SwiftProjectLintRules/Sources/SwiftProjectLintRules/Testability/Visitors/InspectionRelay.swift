import SwiftSyntax

/// A closure ViewInspector calls with the inspected view: `sut.inspect { view in … }`,
/// `sut.inspection.inspect(after:) { view in … }`, `sut.on(\.didAppear) { view in … }`. A
/// predicate passed to `find` is not one — its parameter is a candidate, not a root.
struct InspectionRelay {
    /// The view being inspected — `sut` in all three spellings above.
    let subject: ExprSyntax?

    /// `View.inspect(function:file:line:inspection:)` and the emissary's
    /// `inspect(after:onReceive:function:file:line:_:)`.
    private static let relayLabels: Set<String> = ["after", "onReceive", "function", "file", "line", "inspection"]

    init?(_ closure: ClosureExprSyntax) {
        guard let call = Self.enclosingCall(of: closure),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self) else {
            return nil
        }
        switch member.declName.baseName.text {
        case "inspect":
            let labels = call.arguments.compactMap { $0.label?.text }
            guard labels.allSatisfy(Self.relayLabels.contains) else { return nil }

        case "on":
            guard call.arguments.first?.expression.is(KeyPathExprSyntax.self) == true else { return nil }

        default:
            return nil
        }
        // `sut.inspection.inspect { }` inspects `sut`; the emissary is only the relay. It may be
        // optional: `sut.inspection?.inspect { }`.
        let base = member.base.map(InspectionChainEvaluator.unwrapped)
        if let emissary = base?.as(MemberAccessExprSyntax.self), emissary.declName.baseName.text == "inspection" {
            subject = emissary.base
        } else {
            subject = base
        }
    }

    static func enclosingCall(of closure: ClosureExprSyntax) -> FunctionCallExprSyntax? {
        var node = closure.parent
        while let current = node {
            if let call = current.as(FunctionCallExprSyntax.self) { return call }
            let passesThrough = current.is(LabeledExprSyntax.self)
                || current.is(LabeledExprListSyntax.self)
                || current.is(MultipleTrailingClosureElementSyntax.self)
                || current.is(MultipleTrailingClosureElementListSyntax.self)
            guard passesThrough else { return nil }
            node = current.parent
        }
        return nil
    }
}
