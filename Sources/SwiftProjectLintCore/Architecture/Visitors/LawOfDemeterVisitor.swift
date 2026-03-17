import Foundation
import SwiftSyntax

/// A SwiftSyntax visitor that detects three-level member access chains (a.b.c)
/// where `a` is a plain identifier (not self/super). Each such "train wreck" exposes
/// knowledge of an object's internal structure and violates the Law of Demeter.
class LawOfDemeterVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        // Require: base is a MemberAccess (second level)
        guard let innerAccess = node.base?.as(MemberAccessExprSyntax.self),
              let root = innerAccess.base else {
            return .visitChildren
        }
        // root must be a terminal (not another MemberAccess) — prevents duplicate reports
        guard !root.is(MemberAccessExprSyntax.self) else { return .visitChildren }
        // Skip self.a.b (very common in ViewModels/Views)
        if let rootRef = root.as(DeclReferenceExprSyntax.self),
           rootRef.baseName.text == "self" {
            return .visitChildren
        }
        // Skip super.a.b — super is SuperExprSyntax, not DeclReferenceExprSyntax
        if root.is(SuperExprSyntax.self) { return .visitChildren }
        // Skip function-call chains (SwiftUI modifier chains, fluent APIs)
        if root.is(FunctionCallExprSyntax.self) { return .visitChildren }

        let rootDesc = root.trimmedDescription
        let chain = "\(rootDesc).\(innerAccess.declName.baseName.text).\(node.declName.baseName.text)"
        addIssue(
            severity: .warning,
            message: "Chain '\(chain)' violates the Law of Demeter — " +
                "code knows too much about '\(rootDesc)'s internal structure",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Ask only immediate collaborators; add a method to '\(rootDesc)' that encapsulates this access",
            ruleName: .lawOfDemeter
        )
        return .visitChildren
    }
}
