import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects a ViewInspector test that hosts a view and only *then* inspects it.
///
/// ViewInspector evaluates a view's `body` outside SwiftUI unless the view is
/// hosted. For a view reading `@Environment(SomeType.self)` — the `@Observable`
/// form, which has no default value — that out-of-tree evaluation **traps**
/// inside `EnvironmentValues.subscript.getter` rather than failing. A trap kills
/// the test process, so every test scheduled alongside it is reported failed at
/// 0.000s with no assertion message, and the set differs run to run. The
/// reported crash site names neither ViewInspector nor the offending test.
///
/// Measured on macOS 27 against a minimal reproduction:
///
/// | shape | result |
/// |---|---|
/// | `.environment(obj)` then `.inspect()` | traps |
/// | `ViewHosting.host(…)` then `.inspect()` | traps |
/// | inspection registered, then hosted | passes |
///
/// Only the last works, and it is what ViewInspector's maintainer prescribes:
/// hosting is the last step, after the inspection is set up.
///
/// Two shapes are correct and must not be flagged:
///
/// ```swift
/// // XCTest: inspection registered first, host after.
/// let exp = sut.inspection.inspect { view in … }
/// ViewHosting.host(view: sut.environmentObject(model))
/// wait(for: [exp], timeout: 0.1)
///
/// // async: the inspection is nested *inside* the hosting scope.
/// try await ViewHosting.host(sut.environment(model)) {
///     try await sut.inspection.inspect { view in … }
/// }
/// ```
///
/// The nested form places `ViewHosting.host` textually first, so a naive
/// position comparison would flag it. This visitor only compares *sibling*
/// statements: if one statement contains both calls, the inspection is nested
/// inside the hosting scope and the ordering is correct by construction.
final class ViewHostingBeforeInspectionVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body else { return .visitChildren }

        var hostStatementIndex: Int?
        var inspectStatementIndex: Int?
        var offendingInspect: Syntax?

        for (index, statement) in body.statements.enumerated() {
            let hosts = Self.containsViewHosting(statement)
            let inspects = Self.firstInspection(in: statement)

            // Both in one statement means the inspection is nested inside the
            // hosting closure — the correct async shape.
            if hosts, inspects != nil { continue }

            if hosts, hostStatementIndex == nil {
                hostStatementIndex = index
            }
            if let found = inspects, inspectStatementIndex == nil {
                inspectStatementIndex = index
                offendingInspect = found
            }
        }

        guard let hostIndex = hostStatementIndex,
              let inspectIndex = inspectStatementIndex,
              hostIndex < inspectIndex,
              let anchor = offendingInspect else {
            return .visitChildren
        }

        addIssue(
            severity: .error,
            message: "ViewHosting.host(…) runs before the view is inspected — inspect after "
                + "hosting evaluates the body out-of-tree, which traps rather than fails",
            filePath: getFilePath(for: anchor),
            lineNumber: getLineNumber(for: anchor),
            suggestion: "Register the inspection first and let hosting drive it: either "
                + "`let exp = sut.inspection.inspect { … }` before `ViewHosting.host(…)`, or "
                + "nest the inspection inside `try await ViewHosting.host(sut) { … }`.",
            ruleName: .viewHostingBeforeInspection
        )
        return .visitChildren
    }

    // MARK: - Detection

    /// Whether the statement calls `ViewHosting.host(…)` anywhere within it.
    private static func containsViewHosting(_ statement: CodeBlockItemSyntax) -> Bool {
        SyntaxSearch.firstCall(in: Syntax(statement)) { call in
            guard let member = call.calledExpression.as(MemberAccessExprSyntax.self),
                  member.declName.baseName.text == "host",
                  let base = member.base?.as(DeclReferenceExprSyntax.self) else {
                return false
            }
            return base.baseName.text == "ViewHosting"
        } != nil
    }

    /// The first inspection call in the statement — either ViewInspector's
    /// `.inspect()` entry point or the `inspection.inspect { }` relay.
    private static func firstInspection(in statement: CodeBlockItemSyntax) -> Syntax? {
        SyntaxSearch.firstCall(in: Syntax(statement)) { call in
            guard let member = call.calledExpression.as(MemberAccessExprSyntax.self) else {
                return false
            }
            return member.declName.baseName.text == "inspect"
        }
    }
}

/// Small search helper: the first `FunctionCallExprSyntax` under `root`
/// satisfying `predicate`, in source order.
enum SyntaxSearch {

    static func firstCall(
        in root: Syntax,
        where predicate: (FunctionCallExprSyntax) -> Bool
    ) -> Syntax? {
        if let call = root.as(FunctionCallExprSyntax.self), predicate(call) {
            return root
        }
        for child in root.children(viewMode: .sourceAccurate) {
            if let found = firstCall(in: child, where: predicate) {
                return found
            }
        }
        return nil
    }
}
