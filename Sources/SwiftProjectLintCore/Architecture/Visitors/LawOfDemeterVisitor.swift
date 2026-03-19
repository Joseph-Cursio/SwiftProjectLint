import Foundation
import SwiftSyntax

/// A SwiftSyntax visitor that detects deep member access chains (a.b.c.d or deeper)
/// where `a` is a plain identifier (not self/super). Deep chains expose
/// knowledge of an object's internal structure and violate the Law of Demeter.
///
/// Chains of 2 dots (a.b.c) are considered idiomatic in Swift and not flagged.
class LawOfDemeterVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    /// Minimum number of dots to trigger a warning. 3 means a.b.c.d is flagged.
    private static let minChainDepth = 3

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        // Only report from the outermost MemberAccessExpr to avoid duplicates.
        // If our parent is also a MemberAccessExpr, we're not the outermost.
        if node.parent?.is(MemberAccessExprSyntax.self) == true {
            return .visitChildren
        }

        // Walk down the chain to measure depth and collect components
        var components: [String] = [node.declName.baseName.text]
        var current: ExprSyntax? = node.base
        while let member = current?.as(MemberAccessExprSyntax.self) {
            components.append(member.declName.baseName.text)
            current = member.base
        }

        // current is now the root expression
        guard let root = current else { return .visitChildren }

        // Skip self.a.b.c — very common in ViewModels/Views
        if let rootRef = root.as(DeclReferenceExprSyntax.self),
           rootRef.baseName.text == "self" {
            return .visitChildren
        }
        // Skip super.a.b.c
        if root.is(SuperExprSyntax.self) { return .visitChildren }
        // Skip function-call chains (SwiftUI modifier chains, fluent APIs)
        if root.is(FunctionCallExprSyntax.self) { return .visitChildren }

        // components has the member names in reverse order; add the root
        if let rootRef = root.as(DeclReferenceExprSyntax.self) {
            components.append(rootRef.baseName.text)
        } else {
            components.append(root.trimmedDescription)
        }

        // Total dots = components.count - 1 (e.g., a.b.c.d has 3 dots, 4 components)
        let dotCount = components.count - 1
        guard dotCount >= Self.minChainDepth else { return .visitChildren }

        let chain = components.reversed().joined(separator: ".")
        let rootDesc = components.last ?? "unknown"
        addIssue(
            severity: .warning,
            message: "Chain '\(chain)' has \(dotCount) levels of nesting — " +
                "code knows too much about '\(rootDesc)'s internal structure",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Ask only immediate collaborators; add a method to '\(rootDesc)' that encapsulates this access",
            ruleName: .lawOfDemeter
        )
        return .visitChildren
    }
}
