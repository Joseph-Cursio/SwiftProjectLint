import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects a cycle in a reducer's **synchronous** action-dispatch graph —
/// e.g. `case .start: return .send(.refresh)` together with
/// `case .refresh: return .send(.start)`, which loop forever.
///
/// The graph is built from `.send(.X)` Effect calls inside a `switch action`
/// (the TCA reducer convention). Sends inside `.run { send in … }` closures use
/// the closure's `send` parameter (a plain call, not `.send`) and are **excluded**
/// — those cross an async boundary and usually terminate (timers, request /
/// response), so counting them would produce false positives.
///
/// **Caveat:** a conditional re-dispatch (`if cond { return .send(.x) }`) appears
/// in the static graph but may terminate dynamically — so a flagged cycle is a
/// "verify this terminates," not a proof of an infinite loop. Motivated by a TCA
/// state-consistency review.
final class EffectCycleVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Visit

    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        guard isActionSwitch(node) else { return .visitChildren }

        var graph: [String: Set<String>] = [:]
        for caseElement in node.cases {
            guard case let .switchCase(switchCase) = caseElement else { continue }
            let names = caseNames(in: switchCase)
            guard names.isEmpty == false else { continue }
            let sends = synchronousSends(in: switchCase)
            for name in names {
                graph[name, default: []].formUnion(sends)
            }
        }

        if let cycle = findCycle(in: graph) {
            addIssue(node: Syntax(node), variables: ["cycle": cycle.joined(separator: " → ")])
        }
        return .visitChildren
    }

    // MARK: - Reducer recognition

    /// Returns `true` when the switch subject is the bare identifier `action`.
    private func isActionSwitch(_ node: SwitchExprSyntax) -> Bool {
        node.subject.as(DeclReferenceExprSyntax.self)?.baseName.text == "action"
    }

    // MARK: - Case labels → action names

    private func caseNames(in switchCase: SwitchCaseSyntax) -> [String] {
        guard let label = switchCase.label.as(SwitchCaseLabelSyntax.self) else { return [] }
        return label.caseItems.compactMap { item in
            leadingMemberName(in: Syntax(item.pattern))
        }
    }

    /// First leading-dot member access in `node` (e.g. `.start` → `"start"`,
    /// `.response(let v)` → `"response"`).
    private func leadingMemberName(in node: Syntax) -> String? {
        if let member = node.as(MemberAccessExprSyntax.self), member.base == nil {
            return member.declName.baseName.text
        }
        for child in node.children(viewMode: .sourceAccurate) {
            if let found = leadingMemberName(in: child) { return found }
        }
        return nil
    }

    // MARK: - Case body → synchronous `.send(.X)` targets

    /// Action names dispatched synchronously via `.send(.X)` (Effect form) in the
    /// arm. Plain `send(.X)` calls inside `.run` closures are intentionally
    /// skipped — only the `.send` member-access form counts.
    private func synchronousSends(in switchCase: SwitchCaseSyntax) -> Set<String> {
        var result: Set<String> = []
        collectSends(in: Syntax(switchCase.statements), into: &result)
        return result
    }

    private func collectSends(in node: Syntax, into result: inout Set<String>) {
        if let call = node.as(FunctionCallExprSyntax.self),
           let callee = call.calledExpression.as(MemberAccessExprSyntax.self),
           callee.declName.baseName.text == "send",
           let firstArg = call.arguments.first?.expression,
           let actionName = leadingMemberName(in: Syntax(firstArg)) {
            result.insert(actionName)
        }
        for child in node.children(viewMode: .sourceAccurate) {
            collectSends(in: child, into: &result)
        }
    }

    // MARK: - Cycle detection

    /// Returns the first cycle found as a path (`["a", "b", "a"]`), or `nil`.
    private func findCycle(in graph: [String: Set<String>]) -> [String]? {
        var visited: Set<String> = []
        var stack: [String] = []
        var inStack: Set<String> = []

        func dfs(_ node: String) -> [String]? {
            visited.insert(node)
            stack.append(node)
            inStack.insert(node)
            for next in (graph[node] ?? []).sorted() {
                if inStack.contains(next) {
                    if let index = stack.firstIndex(of: next) {
                        return Array(stack[index...]) + [next]
                    }
                } else if visited.contains(next) == false, let cycle = dfs(next) {
                    return cycle
                }
            }
            stack.removeLast()
            inStack.remove(node)
            return nil
        }

        for node in graph.keys.sorted() where visited.contains(node) == false {
            if let cycle = dfs(node) { return cycle }
        }
        return nil
    }
}
