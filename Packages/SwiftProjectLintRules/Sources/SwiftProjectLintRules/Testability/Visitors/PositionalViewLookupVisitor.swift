import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects a ViewInspector test that reaches a view by walking to it rather than searching for it.
///
/// ```swift
/// try sut.inspect().vStack().hStack(1).button(0)   // walks
/// try sut.inspect().find(viewWithAccessibilityIdentifier: "increment")   // searches
/// ```
///
/// A walk is a description of the layout. Swap two siblings and `hStack(1)` quietly reaches the
/// other one, so the test checks the wrong view; extract a subview, wrap one in a container, or let
/// the compiler insert a wrapper — Swift 6.0 put an implicit `AnyView` around every custom view's
/// body — and the chain breaks though nothing a user sees has changed. For that release ViewInspector
/// added `.implicitAnyView()` to 225 lines of its own tests, and none of them was a `find`.
///
/// Four shapes are reported, each read from an inspected root — `.inspect()`, a relay-closure
/// parameter, `self` in `extension InspectableView`, or a local bound to one of those:
/// - an **index**: `hStack(1)`, `view(Row.self, 2)`, `hStack[1]`, `vStack().first`;
/// - an **ordinal over search matches**: `findAll(…)[1]`, `findAll(…).last`, `skipFound: 2`;
/// - a **second structural step** since the last search: `inspect().navigationStack().vStack()`;
/// - **`parent()`**, which always climbs a fixed number of levels.
///
/// Not reported: one step after an anchor (`find(…).text()`, `inspect().text()`), which asserts a
/// type rather than walking; indices into `ForEach` rows, which are data order; named slots
/// (`labelView()`, `sheet()`, `overlay(1)`); and a subject declared in the same test file, whose
/// layout the test owns.
final class PositionalViewLookupVisitor: BasePatternVisitor {

    private var evaluator: InspectionChainEvaluator?
    private var reportedSteps: Set<SyntaxIdentifier> = []

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        guard Self.importsViewInspector(node.statements) else { return .skipChildren }
        let declared = DeclaredViewsCollector()
        declared.walk(node)
        evaluator = InspectionChainEvaluator(declaredViews: declared.declaredViews)
        reportedSteps = []
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        reportPositionalStep(in: ExprSyntax(node))
        return .visitChildren
    }

    override func visit(_ node: SubscriptCallExprSyntax) -> SyntaxVisitorContinueKind {
        reportPositionalStep(in: ExprSyntax(node))
        return .visitChildren
    }

    /// A chain can end in a property — `.count`, `.pathToRoot`, `.isAbsent` — as easily as a call.
    /// A member access that names a method is part of its call, which is read instead.
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        let namesMethod = node.parent?.as(FunctionCallExprSyntax.self)?.calledExpression.id == node.id
        if node.base != nil, namesMethod == false {
            reportPositionalStep(in: ExprSyntax(node))
        }
        return .visitChildren
    }

    /// One report per chain, at its first positional step. Inner links of the chain are visited
    /// too, so only the outermost is read; a step reached from two wrappers is reported once.
    private func reportPositionalStep(in expr: ExprSyntax) {
        guard let evaluator, Self.isOutermostLink(Syntax(expr)),
              let step = evaluator.evaluate(expr).positionalStep,
              reportedSteps.insert(step.node.id).inserted else { return }
        addIssue(
            severity: .warning,
            message: step.message,
            filePath: getFilePath(for: step.node),
            lineNumber: getLineNumber(for: step.node),
            suggestion: step.suggestion,
            ruleName: .positionalViewLookup
        )
    }

    /// Whether `node` is the last link of its chain — not, through any wrapper the chain reader
    /// looks through, the base of a further member access, subscript or call.
    static func isOutermostLink(_ node: Syntax) -> Bool {
        var current = node
        while let wrapper = enclosingWrapper(of: current) {
            current = wrapper
        }
        guard let parent = current.parent else { return true }
        if let member = parent.as(MemberAccessExprSyntax.self) {
            return member.base?.id != current.id
        }
        if let subscriptCall = parent.as(SubscriptCallExprSyntax.self) {
            return subscriptCall.calledExpression.id != current.id
        }
        if let call = parent.as(FunctionCallExprSyntax.self) {
            return call.calledExpression.id != current.id
        }
        return true
    }

    /// The expression wrapping `node` that `InspectionChainEvaluator.unwrapped` would look through.
    private static func enclosingWrapper(of node: Syntax) -> Syntax? {
        var candidate = node.parent
        // An argument sits in a LabeledExpr inside a list: `(x)`, `XCTUnwrap(x)`, `#require(x)`.
        if candidate?.is(LabeledExprSyntax.self) == true {
            candidate = candidate?.parent?.parent
        }
        guard let wrapper = candidate?.as(ExprSyntax.self),
              let inner = InspectionChainEvaluator.wrapped(by: wrapper), inner.id == node.id else {
            return nil
        }
        return Syntax(wrapper)
    }

    /// `import ViewInspector`, at the top level or inside `#if canImport(ViewInspector)`.
    static func importsViewInspector(_ statements: CodeBlockItemListSyntax) -> Bool {
        statements.contains { statement in
            if let importDecl = statement.item.as(ImportDeclSyntax.self) {
                return importDecl.path.contains { $0.name.text == "ViewInspector" }
            }
            guard let ifConfig = statement.item.as(IfConfigDeclSyntax.self) else { return false }
            return ifConfig.clauses.contains { clause in
                guard case .statements(let nested) = clause.elements else { return false }
                return importsViewInspector(nested)
            }
        }
    }
}

extension PositionalStep {

    var message: String {
        switch kind {
        case .indexed(let written):
            return "`.\(written)` picks a view by its position among its siblings — reorder, wrap or "
                + "extract them and the lookup fails, or reaches a different view of the same type"

        case .descent(let written):
            return "`.\(written)` walks a further level down the view tree — wrapping or extracting a "
                + "view, or the compiler inserting a wrapper, breaks the lookup though nothing on screen changed"

        case .parent:
            return "`.parent()` climbs a fixed number of levels — nest the view differently and the "
                + "lookup breaks or reaches a different container"

        case .matchIndex(let written):
            return "`\(written)` picks a search match by where it sits in the tree — reorder the views "
                + "and the test silently checks a different one"

        case .childIndex(let written):
            return "`\(written)` picks a child view by its position — reorder, wrap or extract the "
                + "children and the lookup fails, or reaches a different view of the same type"
        }
    }

    var suggestion: String {
        if case .matchIndex = kind {
            return "Narrow the search to the one view you mean: `find(viewWithAccessibilityIdentifier:)`, "
                + "`find(button:)`, `find(text:)`, or `find(ViewType.Toggle.self, where:)` with a predicate "
                + "naming it."
        }
        if case .parent = kind {
            return "Search for the container instead of climbing to it: "
                + "`find(ViewType.HStack.self, containing: \"…\")`, `find(ViewType.Button.self, "
                + "relation: .parent)`, or tag it with `.accessibilityIdentifier(\"…\")` and use "
                + "`find(viewWithAccessibilityIdentifier:)`."
        }
        return "Search for the view instead of walking to it: tag it with "
            + "`.accessibilityIdentifier(\"…\")` and use `find(viewWithAccessibilityIdentifier:)`, or "
            + "`find(button:)`, `find(text:)`, `find(MyRow.self)`, `find(ViewType.Toggle.self, where:)`."
    }
}
