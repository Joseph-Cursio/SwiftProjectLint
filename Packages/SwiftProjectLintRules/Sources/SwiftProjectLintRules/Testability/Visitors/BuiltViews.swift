import SwiftSyntax

/// The views a declared view's body builds: each statement of `body`, `makeBody`, a `@ViewBuilder`
/// member or a member typed `some View`, that constructs a type — `AppEditor(values: $values)`,
/// through any modifiers applied to it, and the view an `AnyView(…)`, `overlay(…)`, `background(…)`
/// or `mask(…)` is handed. Closures that run actions — `onAppear`, `task`, a `Button`'s action —
/// build none.
enum BuiltViews {

    static func constructed(in members: MemberBlockSyntax) -> Set<String> {
        let statements = Statements()
        for member in members.members where buildsViews(member.decl) {
            statements.walk(member.decl)
        }
        let built = statements.expressions.filter { runsAsAction($0) == false }.flatMap(constructedTypes(by:))
        return Set(built).subtracting(nonViews)
    }

    /// SwiftUI's own views, and the toolbar items, alerts and shapes that ViewInspector names no
    /// accessor after.
    static func isSwiftUIView(_ typeName: String) -> Bool {
        InspectionVocabulary.isSwiftUIViewType(typeName) || buildingBlocks.contains(typeName)
    }

    private static let buildingBlocks: Set<String> = [
        "ToolbarItem", "ToolbarItemGroup", "Alert", "ActionSheet", "Rectangle", "RoundedRectangle",
        "UnevenRoundedRectangle", "Circle", "Capsule", "Ellipse", "ContainerRelativeShape", "Path",
        "AnyShape", "Table", "TableColumn", "TableRow", "Gauge", "Tab", "TupleView", "ModifiedContent"
    ]

    /// Types a statement in a body constructs that are not views: a task, and the marks a `Chart`
    /// is built from.
    private static let nonViews: Set<String> = [
        "Task", "DispatchWorkItem", "BarMark", "LineMark", "PointMark", "AreaMark", "RuleMark",
        "RectangleMark", "SectorMark"
    ]

    private static func buildsViews(_ decl: DeclSyntax) -> Bool {
        if let variable = decl.as(VariableDeclSyntax.self) {
            return isViewBuilder(variable.attributes) || variable.bindings.contains { binding in
                InspectionBindingResolver.identifier(of: binding.pattern) == "body"
                    || binding.typeAnnotation.map { isViewType($0.type) } == true
            }
        }
        if let function = decl.as(FunctionDeclSyntax.self) {
            return ["body", "makeBody"].contains(function.name.text) || isViewBuilder(function.attributes)
                || function.signature.returnClause.map { isViewType($0.type) } == true
        }
        return false
    }

    private static func isViewBuilder(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "ViewBuilder" }
    }

    /// `some View` or `AnyView`: a member factored out of a body.
    private static func isViewType(_ type: TypeSyntax) -> Bool {
        ["some View", "AnyView", "some SwiftUI.View"].contains(type.trimmedDescription)
    }

    /// `AppEditor(…)`, `AppEditor(…).padding()`, `Text("x").overlay(Badge())`: the type at the root
    /// of the statement's chain, and any view a wrapper or a view-taking modifier on the way is handed.
    private static func constructedTypes(by statement: ExprSyntax) -> [String] {
        var found: [String] = []
        var current = statement
        while true {
            if let call = current.as(FunctionCallExprSyntax.self) {
                if let handed = viewHanded(to: call) {
                    found += constructedTypes(by: handed)
                }
                if let typeName = InspectionChainEvaluator.constructedType(by: call) {
                    return typeName == "AnyView" ? found : found + [typeName]
                }
                current = call.calledExpression
            } else if let member = current.as(MemberAccessExprSyntax.self), let base = member.base {
                current = base
            } else {
                return found
            }
        }
    }

    /// The view `AnyView(…)`, `overlay(…)`, `background(…)` or `mask(…)` is handed as its first,
    /// unlabelled argument.
    private static func viewHanded(to call: FunctionCallExprSyntax) -> ExprSyntax? {
        let callee = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
            ?? call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
        guard let callee, ["AnyView", "overlay", "background", "mask"].contains(callee),
              let first = call.arguments.first, first.label == nil else {
            return nil
        }
        return first.expression
    }

    /// Inside a closure passed to `onAppear`, `task`, `onChange(of:)`, labelled `action:` or
    /// `onIncrement:`, or a `Button`'s action written as its trailing closure.
    private static func runsAsAction(_ statement: ExprSyntax) -> Bool {
        var node = Syntax(statement).parent
        while let current = node {
            if let closure = current.as(ClosureExprSyntax.self), isAction(closure) {
                return true
            }
            node = current.parent
        }
        return false
    }

    private static let actionLabels: Set<String> = [
        "action", "onIncrement", "onDecrement", "onEditingChanged", "onCommit", "perform"
    ]

    private static func isAction(_ closure: ClosureExprSyntax) -> Bool {
        if let label = closure.parent?.as(LabeledExprSyntax.self)?.label?.text, actionLabels.contains(label) {
            return true
        }
        // `Button("Save") { … }` and `Button { … } label: { … }`: without `action:`, the trailing
        // closure is the action.
        if let call = closure.parent?.as(FunctionCallExprSyntax.self), call.trailingClosure?.id == closure.id,
           call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Button" {
            return call.arguments.contains { $0.label?.text == "action" } == false
        }
        let callee = InspectionRelay.enclosingCall(of: closure)?.calledExpression
            .as(MemberAccessExprSyntax.self)?.declName.baseName.text ?? ""
        return callee == "task" || callee == "refreshable" || isActionModifier(callee)
    }

    /// `onAppear`, `onTapGesture`, `onChange`: `on` followed by a capital.
    private static func isActionModifier(_ name: String) -> Bool {
        name.hasPrefix("on") && name.dropFirst(2).first?.isUppercase == true
    }
}

/// Every expression statement, and every `return` value, in the syntax walked.
private final class Statements: SyntaxVisitor {
    private(set) var expressions: [ExprSyntax] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
        if let returned = node.item.as(ReturnStmtSyntax.self)?.expression {
            expressions.append(returned)
        } else if let expression = node.item.as(ExprSyntax.self) {
            expressions.append(expression)
        }
        return .visitChildren
    }
}
