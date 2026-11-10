import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Counts the distinct service-like types constructed anywhere inside one body, and notes
/// whether the body keeps anything past its own return.
///
/// Every construction is counted, not only the ones the rule would report:
/// `self.runner = SwiftLintRunner()` is an assignment rather than a variable declaration, and
/// `try await BeadStore(path:)` wraps its call in two expressions, so a count of *findings*
/// would read `assignStatelessServices` — six services wired in eight lines — as reaching for
/// one.
final class ServiceConstructionCounter: SyntaxVisitor {

    private(set) var typeNames: Set<String> = []

    /// Whether the body assigns to something that outlives it.
    ///
    /// `self.chatSessionStore = store` is the obvious spelling. The bare form matters as much:
    /// `handler = newHandler` inside `ExtensionServiceContainer`, `workspaceIndexer = indexer`
    /// inside an `AppState` extension, and `_ruleRegistry = State(initialValue: registry)` in a
    /// SwiftUI `App`\'s `init` all assign to a stored property without writing `self.`. Told
    /// apart from a local reassignment by name: every `let`/`var` the body itself binds is
    /// collected, and a target outside that set is a member.
    var retainsBeyondBody: Bool {
        assignedNames.contains { !locallyBoundNames.contains($0) } || assignsThroughSelf
    }

    private var locallyBoundNames: Set<String> = []
    private var assignedNames: Set<String> = []
    private var assignsThroughSelf = false

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let name = DirectInstantiationVisitor.constructedTypeName(of: node.calledExpression),
           ServiceTypeSuffix.matches(name) {
            typeNames.insert(name)
        }
        return .visitChildren
    }

    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        if let identifier = node.pattern.as(IdentifierPatternSyntax.self) {
            locallyBoundNames.insert(identifier.identifier.text)
        }
        return .visitChildren
    }

    /// Assignment is read off `SequenceExprSyntax`, not `InfixOperatorExprSyntax`.
    ///
    /// An unfolded tree — which is what `Parser.parse` produces, and what every visitor here
    /// walks — represents `self.store = store` as a three-element sequence whose middle
    /// element is the `AssignmentExprSyntax`. `InfixOperatorExprSyntax` appears only after
    /// operator folding, which needs an operator table the linter never builds. Written the
    /// other way first, this gate compiled, its tests passed against hand-built trees, and it
    /// removed exactly nothing from the corpus.
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Array(node.elements)
        guard elements.count >= 2,
              elements[1].as(AssignmentExprSyntax.self) != nil else { return .visitChildren }
        let target = elements[0]
        if let member = target.as(MemberAccessExprSyntax.self),
           member.base?.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind == .keyword(.self) {
            assignsThroughSelf = true
        }
        if let reference = target.as(DeclReferenceExprSyntax.self) {
            assignedNames.insert(reference.baseName.text)
        }
        return .visitChildren
    }
}
