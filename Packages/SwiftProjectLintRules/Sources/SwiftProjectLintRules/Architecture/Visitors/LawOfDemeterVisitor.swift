import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects deep member access chains (a.b.c.d or deeper)
/// where `a` is a plain identifier (not self/super). Deep chains expose
/// knowledge of an object's internal structure and violate the Law of Demeter.
///
/// Chains of 2 dots (a.b.c) are considered idiomatic in Swift and not flagged.
class LawOfDemeterVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    /// One finding per *reach-through*, not per occurrence.
    ///
    /// Keyed by the enclosing declaration and the penultimate component — the thing being reached
    /// into. Measured on two repositories before this existed: five sort comparators in
    /// SwiftInferProperties produced **48 findings for one missing `Comparable` conformance**, and
    /// eleven DTO-flattening constructors in SwiftAssist produced eleven for zero problems. The
    /// number never described anything a reader would act on that many times, and the largest
    /// cluster was the *easiest* fix — so counting occurrences inverted the priority.
    ///
    /// The key is the penultimate component rather than the root because that is what the
    /// encapsulation goes on: `lhs.member.location.file` and `rhs.member.location.line` are the same
    /// problem with `location`, and reporting them under `lhs` and `rhs` would split one fix in two.
    private var reportedReachThroughs: Set<ReachThrough> = []

    private struct ReachThrough: Hashable {
        /// Byte offset of the enclosing declaration, or 0 at file scope.
        let declarationPosition: Int
        /// The component being reached into — the penultimate hop.
        let target: String
    }

    /// Minimum number of dots to trigger a warning. 3 means a.b.c.d is flagged.
    private static let minChainDepth = 3

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        self.currentFilePath = filePath
    }

    override func reset() {
        super.reset()
        reportedReachThroughs = []
    }

    /// The declaration a node sits in, identified by position. Chains in different functions are
    /// different problems even when they name the same target; chains in one function are one.
    func enclosingDeclarationPosition(of node: Syntax) -> Int {
        var current: Syntax? = node.parent
        while let syntax = current {
            if Self.isDeclarationBoundary(syntax) {
                return syntax.positionAfterSkippingLeadingTrivia.utf8Offset
            }
            current = syntax.parent
        }
        return 0
    }

    /// The declarations a reach-through is scoped to. Split out from the walk above so the walk
    /// stays under the cyclomatic-complexity limit these five `is` checks pushed it over.
    static func isDeclarationBoundary(_ syntax: Syntax) -> Bool {
        syntax.is(FunctionDeclSyntax.self) || syntax.is(InitializerDeclSyntax.self)
            || syntax.is(AccessorDeclSyntax.self) || syntax.is(VariableDeclSyntax.self)
            || syntax.is(SubscriptDeclSyntax.self)
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        // Only report from the outermost MemberAccessExpr to avoid duplicates.
        if node.parent?.is(MemberAccessExprSyntax.self) == true {
            return .visitChildren
        }
        // Skip chains that are the callee of a function call
        if node.parent?.is(FunctionCallExprSyntax.self) == true {
            return .visitChildren
        }

        // Test and fixture files are full of deliberately shaped sample code.
        if isTestOrFixtureFile() { return .visitChildren }

        guard let (orderedComponents, dotCount) = DemeterChainFilter.qualifyingChain(
            from: node, minChainDepth: Self.minChainDepth
        ) else {
            return .visitChildren
        }

        let chain = orderedComponents.joined(separator: ".")
        let rootDesc = orderedComponents.first ?? "unknown"
        let target = orderedComponents.count >= 2
            ? orderedComponents[orderedComponents.count - 2]
            : rootDesc

        // One finding per reach-through. A second chain into the same target from the same
        // declaration is the same problem and the same fix.
        let key = ReachThrough(
            declarationPosition: enclosingDeclarationPosition(of: Syntax(node)),
            target: target
        )
        guard reportedReachThroughs.insert(key).inserted else { return .visitChildren }

        addIssue(
            severity: .info,
            message: "Chain '\(chain)' has \(dotCount) levels of nesting — " +
                "code knows too much about '\(target)'s internal structure. Reported once per "
                + "declaration that reaches into '\(target)', however many times it does so",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Ask only immediate collaborators; add a method or conformance to "
                + "'\(target)' that encapsulates this access",
            ruleName: .lawOfDemeter
        )
        return .visitChildren
    }
}
