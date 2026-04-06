import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `withTaskGroup`/`withThrowingTaskGroup` patterns where tasks are
/// added in a loop without concurrency limiting (backpressure).
///
/// When `group.addTask` is called inside a `for`/`while` loop without a
/// corresponding `group.next()` in the same loop, the runtime may spawn
/// thousands of concurrent tasks, exhausting thread pool resources.
final class UnboundedTaskGroupVisitor: BasePatternVisitor {

    /// The parameter name bound to the task group (e.g. "group" in `{ group in ...}`).
    private var taskGroupParamNames: [String] = []

    /// Tracks nesting: how deep we are inside task group closures.
    private var taskGroupDepth = 0

    /// Tracks loops inside task groups. Each entry is (loopNode ID, hasBackpressure).
    private var loopStack: [(loopID: SyntaxIdentifier, hasBackpressure: Bool)] = []

    /// Collects addTask call sites inside loops that lack backpressure,
    /// keyed by loop ID.
    private var addTaskSites: [SyntaxIdentifier: [Syntax]] = [:]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Detect withTaskGroup / withThrowingTaskGroup

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Check if this is a withTaskGroup or withThrowingTaskGroup call
        if let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
           isTaskGroupFunction(declRef.baseName.text) {
            if let closure = node.trailingClosure,
               let paramName = extractClosureParamName(closure) {
                taskGroupParamNames.append(paramName)
                taskGroupDepth += 1
            }
        }

        // Check for group.addTask inside a loop
        if taskGroupDepth > 0,
           loopStack.isEmpty == false,
           isAddTaskCall(node) {
            let loopID = loopStack[loopStack.count - 1].loopID
            addTaskSites[loopID, default: []].append(Syntax(node))
        }

        // Check for group.next() inside a loop (backpressure)
        if taskGroupDepth > 0,
           loopStack.isEmpty == false,
           isNextCall(node) {
            loopStack[loopStack.count - 1].hasBackpressure = true
        }

        return .visitChildren
    }

    // MARK: - Track for/while loops inside task groups

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        if taskGroupDepth > 0 {
            // Check for `for await ... in group` (consuming pattern = backpressure)
            let isForAwaitOverGroup = node.awaitKeyword != nil
                && isGroupReference(node.sequence)
            loopStack.append((loopID: node.id, hasBackpressure: isForAwaitOverGroup))
        }
        return .visitChildren
    }

    override func visitPost(_ node: ForStmtSyntax) {
        guard taskGroupDepth > 0,
              let last = loopStack.last,
              last.loopID == node.id else { return }

        let entry = loopStack.removeLast()
        if entry.hasBackpressure == false, let sites = addTaskSites[node.id] {
            for site in sites {
                reportUnboundedTaskGroup(at: site)
            }
        }
        addTaskSites.removeValue(forKey: node.id)
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        if taskGroupDepth > 0 {
            loopStack.append((loopID: node.id, hasBackpressure: false))
        }
        return .visitChildren
    }

    override func visitPost(_ node: WhileStmtSyntax) {
        guard taskGroupDepth > 0,
              let last = loopStack.last,
              last.loopID == node.id else { return }

        let entry = loopStack.removeLast()
        if entry.hasBackpressure == false, let sites = addTaskSites[node.id] {
            for site in sites {
                reportUnboundedTaskGroup(at: site)
            }
        }
        addTaskSites.removeValue(forKey: node.id)
    }

    // MARK: - Clean up task group scope on closure exit

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        return .visitChildren
    }

    override func visitPost(_ node: ClosureExprSyntax) {
        // If this closure's parameter matches the current task group param, pop it
        if let signature = node.signature,
           taskGroupDepth > 0 {
            let paramName = extractParamNameFromSignature(signature)
            if let paramName,
               let lastGroup = taskGroupParamNames.last,
               paramName == lastGroup {
                taskGroupParamNames.removeLast()
                taskGroupDepth -= 1
            }
        }
    }

    // MARK: - Helpers

    private func isTaskGroupFunction(_ name: String) -> Bool {
        name == "withTaskGroup" || name == "withThrowingTaskGroup"
    }

    private func isAddTaskCall(_ node: FunctionCallExprSyntax) -> Bool {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "addTask",
              let base = memberAccess.base?.as(DeclReferenceExprSyntax.self) else {
            return false
        }
        return taskGroupParamNames.contains(base.baseName.text)
    }

    private func isNextCall(_ node: FunctionCallExprSyntax) -> Bool {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "next",
              let base = memberAccess.base?.as(DeclReferenceExprSyntax.self) else {
            return false
        }
        return taskGroupParamNames.contains(base.baseName.text)
    }

    private func isGroupReference(_ expr: ExprSyntax) -> Bool {
        guard let declRef = expr.as(DeclReferenceExprSyntax.self) else { return false }
        return taskGroupParamNames.contains(declRef.baseName.text)
    }

    private func extractClosureParamName(_ closure: ClosureExprSyntax) -> String? {
        guard let signature = closure.signature else { return nil }
        return extractParamNameFromSignature(signature)
    }

    private func extractParamNameFromSignature(_ signature: ClosureSignatureSyntax) -> String? {
        guard let paramClause = signature.parameterClause else { return nil }
        switch paramClause {
        case .simpleInput(let params):
            return params.first?.name.text
        case .parameterClause(let clause):
            return clause.parameters.first?.firstName.text
        }
    }

    private func reportUnboundedTaskGroup(at node: Syntax) {
        addIssue(
            severity: .warning,
            message: "Task group adds tasks in a loop without concurrency "
                + "limiting — may exhaust thread pool resources",
            filePath: getFilePath(for: node),
            lineNumber: getLineNumber(for: node),
            suggestion: "Add backpressure by calling 'group.next()' inside the loop, "
                + "or limit concurrency with a counter.",
            ruleName: .unboundedTaskGroup
        )
    }
}
