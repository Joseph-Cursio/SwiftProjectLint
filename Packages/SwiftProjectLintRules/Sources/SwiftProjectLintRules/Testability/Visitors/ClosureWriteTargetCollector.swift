import Foundation
import SwiftSyntax

/// What a closure body writes to, split by whether the write lands in view-local storage.
///
/// `directWrites` are bare-identifier assignments and `toggle()` — the shapes that reach a
/// `@State` property itself. `otherWrites` is everything else that mutates: a member assignment
/// (`viewModel.error = nil`), or a mutating call on a receiver (`items.append(x)`). One entry in
/// `otherWrites` disqualifies the whole closure, because the gate's claim is about the *only*
/// thing the body does.
final class ClosureWriteTargetCollector: SyntaxVisitor {

    private(set) var directWrites: Set<String> = []
    private(set) var otherWrites: Set<String> = []

    /// Calls that mutate their receiver. An allowlist, for the reason `CallbackSurface` gives:
    /// an unlisted name is a missed disqualification and so a kept finding, which is the safe
    /// direction, while a wrong inference gates something real.
    private static let mutatingCalls: Set<String> = [
        "append", "insert", "remove", "removeAll", "removeFirst", "removeLast", "removeValue",
        "sort", "reverse", "popLast", "formUnion", "subtract",
    ]

    /// Assignment is read off `SequenceExprSyntax`, not `InfixOperatorExprSyntax`: an unfolded
    /// tree — what `Parser.parse` produces and what every visitor here walks — represents
    /// `flag = true` as a three-element sequence. `InfixOperatorExprSyntax` appears only after
    /// operator folding, which the linter never does.
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Array(node.elements)
        guard elements.count >= 2, Self.isAssignment(elements[1]) else { return .visitChildren }
        record(target: elements[0])
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
              let receiver = member.base?.as(DeclReferenceExprSyntax.self) else {
            return .visitChildren
        }
        let name = member.declName.baseName.text
        if name == "toggle" {
            directWrites.insert(receiver.baseName.text)
        } else if Self.mutatingCalls.contains(name) {
            otherWrites.insert(receiver.baseName.text)
        }
        return .visitChildren
    }

    private func record(target: ExprSyntax) {
        if let reference = target.as(DeclReferenceExprSyntax.self) {
            directWrites.insert(reference.baseName.text)
            return
        }
        if let member = target.as(MemberAccessExprSyntax.self) {
            otherWrites.insert(member.description.trimmingCharacters(in: .whitespaces))
            return
        }
        // A subscript, a tuple destructuring, anything else — treat as a write that is not a
        // plain `@State` assignment rather than ignoring it.
        otherWrites.insert(target.description.trimmingCharacters(in: .whitespaces))
    }

    /// `=` is an `AssignmentExprSyntax`; `+=` and friends are binary operators whose text ends
    /// in `=` without being a comparison.
    static func isAssignment(_ element: ExprSyntax) -> Bool {
        if element.is(AssignmentExprSyntax.self) { return true }
        guard let binary = element.as(BinaryOperatorExprSyntax.self) else { return false }
        let text = binary.operator.text
        return text.hasSuffix("=") && !["==", "!=", "<=", ">=", "==="].contains(text)
    }
}
