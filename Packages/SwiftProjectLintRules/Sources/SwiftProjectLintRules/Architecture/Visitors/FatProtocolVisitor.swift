import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// Visitor that detects protocols with too many requirements (Interface Segregation violation).
///
/// Protocols with 10 or more requirements suggest the protocol should be broken
/// into smaller, composable protocols following Swift's trait-based composition style.
class FatProtocolVisitor: BasePatternVisitor {

    private static let threshold = 10

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let requirementCount = countRequirements(node)

        if requirementCount >= Self.threshold {
            addIssue(
                node: Syntax(node),
                variables: [
                    "protocolName": node.name.text,
                    "count": "\(requirementCount)"
                ]
            )
        }
        return .visitChildren
    }

    private func countRequirements(_ node: ProtocolDeclSyntax) -> Int {
        var count = 0
        for member in node.memberBlock.members {
            let decl = member.decl
            if decl.is(FunctionDeclSyntax.self)
                || decl.is(VariableDeclSyntax.self)
                || decl.is(InitializerDeclSyntax.self)
                || decl.is(SubscriptDeclSyntax.self)
                || decl.is(AssociatedTypeDeclSyntax.self) {
                count += 1
            }
        }
        return count
    }
}
