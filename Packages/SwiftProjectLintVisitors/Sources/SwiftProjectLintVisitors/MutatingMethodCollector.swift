import SwiftSyntax

/// A project-wide pre-scan collecting the base names of every `mutating func` the project declares
/// — on a struct, an enum, an extension, or as a protocol requirement.
///
/// ## Why a per-file visitor cannot answer this
///
/// The Actor Reentrancy rule asks whether an actor updates the property it guarded on before its
/// first `await`. A write through a method looks like any other call:
///
///     guard gate.isDue(at: now) else { return [] }
///     gate.recordAttempt(at: now)
///     return try await runAnalysis()
///
/// `recordAttempt(at:)` is a write only because `RunGate` declares it `mutating`, and `RunGate`
/// usually lives in another file. The rule's own allowlist covers the standard library
/// (`insert`, `append`, …), so before this collector every project-defined gate type read as
/// "checked but never updated" — a false positive on exactly the code that had fixed the race.
///
/// Names only, with no receiver type: the rule cannot resolve `gate`'s type either, and a call on a
/// stored `var` whose name matches some `mutating func` in the project is a write far more often
/// than not.
public final class MutatingMethodCollector: SyntaxVisitor, TypeCollectorProtocol {

    public var collectedTypes: Set<String> { mutatingMethods }

    private var mutatingMethods: Set<String> = []

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    override public func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.modifiers.contains(where: { $0.name.tokenKind == .keyword(.mutating) }) {
            mutatingMethods.insert(node.name.text)
        }
        return .visitChildren
    }
}
