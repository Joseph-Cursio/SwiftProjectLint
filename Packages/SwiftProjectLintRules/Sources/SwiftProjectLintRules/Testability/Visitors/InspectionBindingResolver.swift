import SwiftSyntax

/// What a name at a use site was bound to, as far as Positional View Lookup needs to know.
enum InspectionBinding {
    /// `let x = <expr>`, or `if let` / `guard let x = <expr>`, with the binding's annotation when
    /// it has one — read when the initializer is not.
    case value(ExprSyntax, annotation: TypeSyntax?)
    /// `for x in <expr>`, or the parameter of a closure iterating `<expr>` — each element.
    case element(ExprSyntax)
    /// A relay-closure parameter, whose `subject` is the view being inspected.
    case relayParameter(subject: ExprSyntax?)
    /// A parameter, property or local typed `InspectableView<…>`.
    case inspectableView(InspectableViewType)
    /// Annotated with a type and nothing else: `var sut: CounterView!`. Not a view under
    /// inspection, but its type says whether the test file owns the subject.
    case declared(TypeSyntax)
    /// Bound, but to something the rule cannot read. Stops the search: an outer binding of the
    /// same name is shadowed.
    case opaque
}

/// Finds the binding a name refers to, by walking outward through the scopes around its use.
///
/// Most positional walks in real tests are split across statements —
/// `let stack = try sut.inspect().vStack()`, then `stack.button(0)` — and each statement alone
/// looks like a single harmless hop. In the 165 ViewInspector test files surveyed for this rule,
/// a third of the positional lookups went through a local, so the rule follows them back.
///
/// Lexical only: a binding is the nearest declaration of the name in an enclosing scope, before
/// the use. Reassignment is not followed. One resolver serves one file; the bindings of each
/// statement list are indexed once, so a long test function is not rescanned for every use.
final class InspectionBindingResolver {

    private typealias Entry = (position: AbsolutePosition, binding: InspectionBinding)
    private var statementIndex: [SyntaxIdentifier: [String: [Entry]]] = [:]
    private var memberIndex: [SyntaxIdentifier: [String: InspectionBinding]] = [:]
    /// Member lists of every type declaration in the file, by name, so an `extension Tests` finds
    /// the properties `class Tests` declares.
    private var typeMembers: [String: [MemberBlockItemListSyntax]]?
    private var conditionIndex: [SyntaxIdentifier: [String: [Entry]]] = [:]
    private var functionReturnTypes: [String: [FunctionReturnTypes.Declaration]]?

    /// `makeProbe()` → `Probe`: the declared return type of a function in this file, looked up in
    /// `owners` in order — the type a call names, or the types around the call and then the file
    /// scope (`nil`). Overloads that disagree on the type give none.
    func returnType(ofFunction name: String, ownedByFirstOf owners: [String?], in root: Syntax) -> String? {
        if functionReturnTypes == nil {
            let collector = FunctionReturnTypes()
            collector.walk(root)
            functionReturnTypes = collector.declarations
        }
        let declarations = functionReturnTypes?[name] ?? []
        for owner in owners {
            let returned = Set(declarations.filter { $0.owner == owner }.map(\.returnType))
            if returned.isEmpty == false {
                return returned.count == 1 ? returned.first : nil
            }
        }
        return nil
    }

    func resolve(_ name: String, from use: Syntax) -> InspectionBinding? {
        resolveWithScope(name, from: use)?.binding
    }

    /// The binding and the scope that makes it: a statement list, a `for` loop, a closure.
    func resolveWithScope(_ name: String, from use: Syntax) -> (binding: InspectionBinding, scope: Syntax)? {
        var child = use
        while let parent = child.parent {
            if let found = binding(named: name, in: parent, enclosing: child) {
                return (found, parent)
            }
            child = parent
        }
        return nil
    }

    /// `Int` in `enum Tab: Int`: the raw type of an enum this file declares.
    func rawType(ofEnum typeName: String, in root: Syntax) -> TypeSyntax? {
        declarations(ofType: typeName, in: root).lazy.compactMap { members in
            members.parent?.parent?.as(EnumDeclSyntax.self)?.inheritanceClause?.inheritedTypes.first?.type
        }.first
    }

    /// `Layout.rowsIndex`: a stored property of a type this file declares.
    func member(named name: String, ofType typeName: String, in root: Syntax) -> InspectionBinding? {
        for members in declarations(ofType: typeName, in: root) {
            if let found = memberBindings(of: members)[name] {
                return found
            }
        }
        return nil
    }

    /// `self.name`: a stored property of the enclosing type, skipping locals of the same name.
    func resolveProperty(_ name: String, from use: Syntax) -> InspectionBinding? {
        var current = use.parent
        while let scope = current {
            if let members = scope.as(MemberBlockItemListSyntax.self), let found = member(binding: name, in: members) {
                return found
            }
            current = scope.parent
        }
        return nil
    }

    private func binding(named name: String, in scope: Syntax, enclosing child: Syntax) -> InspectionBinding? {
        if let items = scope.as(CodeBlockItemListSyntax.self) {
            return earlierStatement(binding: name, in: items, before: child)
        }
        if let members = scope.as(MemberBlockItemListSyntax.self) {
            return member(binding: name, in: members)
        }
        if let closure = scope.as(ClosureExprSyntax.self) {
            // A capture's initializer — `x` in `[x = x]` — is read outside the closure.
            guard closure.signature?.id != child.id else { return nil }
            return closureParameter(name, of: closure)
        }
        if let parameter = Self.declarationParameter(name, of: scope) {
            return parameter
        }
        if let conditions = conditionScope(of: scope, enclosing: child) {
            let entries = conditionBindings(of: conditions)[name] ?? []
            return entries.last { $0.position < child.position }?.binding
        }
        return Self.localBinding(named: name, in: scope, enclosing: child)
    }

    // MARK: - Statement lists

    private func earlierStatement(
        binding name: String,
        in items: CodeBlockItemListSyntax,
        before child: Syntax
    ) -> InspectionBinding? {
        let index = statementIndex[items.id] ?? Self.index(items)
        statementIndex[items.id] = index
        // A file-scope declaration is visible throughout the file, not only below it.
        let isFileScope = items.parent?.is(SourceFileSyntax.self) == true
        return index[name]?.last { isFileScope || $0.position < child.position }?.binding
    }

    /// Every name each statement binds for the statements after it, in source order.
    private static func index(_ items: CodeBlockItemListSyntax) -> [String: [Entry]] {
        var index: [String: [Entry]] = [:]
        for item in items {
            for (name, binding) in bindings(declaredBy: Syntax(item.item)) {
                index[name, default: []].append((item.position, binding))
            }
        }
        return index
    }

    private static func bindings(declaredBy item: Syntax) -> [(String, InspectionBinding)] {
        if let decl = item.as(VariableDeclSyntax.self) {
            return variableBindings(decl)
        }
        if let guardStmt = item.as(GuardStmtSyntax.self) {
            return guardStmt.conditions.flatMap(conditionBindings)
        }
        if let ifConfig = item.as(IfConfigDeclSyntax.self) {
            // Every branch binds the same names for what follows. The first branch is usually the
            // configuration under test, so it goes last, where a lookup finds it.
            return ifConfig.clauses.reversed().flatMap { clause -> [(String, InspectionBinding)] in
                guard case .statements(let nested) = clause.elements else { return [] }
                return nested.flatMap { bindings(declaredBy: Syntax($0.item)) }
            }
        }
        return []
    }

    // MARK: - Members

    /// A stored property of a type, looked up in the member list, then in the other declarations
    /// of the same type in this file: `class Tests` and its `extension Tests`.
    private func member(binding name: String, in members: MemberBlockItemListSyntax) -> InspectionBinding? {
        if let found = memberBindings(of: members)[name] {
            return found
        }
        guard let typeName = Self.declaredTypeName(owning: members) else { return nil }
        for other in declarations(ofType: typeName, in: Syntax(members).root) where other.id != members.id {
            if let found = memberBindings(of: other)[name] {
                return found
            }
        }
        return nil
    }

    private func memberBindings(of members: MemberBlockItemListSyntax) -> [String: InspectionBinding] {
        if let cached = memberIndex[members.id] { return cached }
        var bindings: [String: InspectionBinding] = [:]
        for member in members {
            if let decl = member.decl.as(VariableDeclSyntax.self) {
                for (name, binding) in Self.variableBindings(decl) where bindings[name] == nil {
                    bindings[name] = binding
                }
            }
            if let ifConfig = member.decl.as(IfConfigDeclSyntax.self) {
                for clause in ifConfig.clauses {
                    guard case .decls(let nested) = clause.elements else { continue }
                    bindings.merge(memberBindings(of: nested)) { first, _ in first }
                }
            }
        }
        memberIndex[members.id] = bindings
        return bindings
    }

    private static func declaredTypeName(owning members: MemberBlockItemListSyntax) -> String? {
        let owner = members.parent?.parent
        if let extensionDecl = owner?.as(ExtensionDeclSyntax.self) {
            return InspectionVocabulary.typeName(extensionDecl.extendedType.trimmedDescription)
        }
        return owner?.as(ClassDeclSyntax.self)?.name.text ?? owner?.as(StructDeclSyntax.self)?.name.text
            ?? owner?.as(EnumDeclSyntax.self)?.name.text ?? owner?.as(ActorDeclSyntax.self)?.name.text
    }

    private func declarations(ofType typeName: String, in root: Syntax) -> [MemberBlockItemListSyntax] {
        if typeMembers == nil {
            let collector = TypeMemberLists()
            collector.walk(root)
            typeMembers = collector.lists
        }
        return typeMembers?[typeName] ?? []
    }

    /// `var a, b: InspectableView<…>`: only `b` carries the annotation in the syntax tree, but it
    /// types `a` too.
    private static func variableBindings(_ decl: VariableDeclSyntax) -> [(String, InspectionBinding)] {
        let bindings = Array(decl.bindings)
        return bindings.indices.flatMap { index -> [(String, InspectionBinding)] in
            let binding = bindings[index]
            guard binding.typeAnnotation == nil, binding.initializer == nil else { return variableBindings(binding) }
            let shared = bindings[index...].lazy.compactMap { $0.typeAnnotation?.type }.first
            return variableBindings(binding, annotation: shared)
        }
    }

    private static func variableBindings(
        _ binding: PatternBindingSyntax,
        annotation sharedAnnotation: TypeSyntax? = nil
    ) -> [(String, InspectionBinding)] {
        guard let name = identifier(of: binding.pattern) else {
            return boundNames(in: binding.pattern).map { ($0, .opaque) }
        }
        let annotation = binding.typeAnnotation?.type ?? sharedAnnotation
        if let value = binding.initializer?.value {
            return [(name, .value(value, annotation: annotation))]
        }
        if let annotation {
            return [(name, declaredBinding(annotation))]
        }
        return [(name, .opaque)]
    }

    // MARK: - Conditions, loops, cases

    /// The conditions whose bindings a use sees: a later condition sees an earlier one's, and
    /// `if let x = …` and `while let x = …` bind for their body.
    private func conditionScope(of scope: Syntax, enclosing child: Syntax) -> ConditionElementListSyntax? {
        if let conditions = scope.as(ConditionElementListSyntax.self) {
            return conditions
        }
        if let ifExpr = scope.as(IfExprSyntax.self), child.id == ifExpr.body.id {
            return ifExpr.conditions
        }
        if let whileStmt = scope.as(WhileStmtSyntax.self), child.id == whileStmt.body.id {
            return whileStmt.conditions
        }
        return nil
    }

    /// Every name a condition list binds, in order. Each list is indexed once.
    private func conditionBindings(of conditions: ConditionElementListSyntax) -> [String: [Entry]] {
        if let cached = conditionIndex[conditions.id] { return cached }
        var index: [String: [Entry]] = [:]
        for element in conditions {
            for (name, binding) in Self.conditionBindings(element) {
                index[name, default: []].append((element.position, binding))
            }
        }
        conditionIndex[conditions.id] = index
        return index
    }

    /// `for x in …` binds for its body; `case let`, `catch` and tuple patterns bind names the rule
    /// cannot read, which shadow any outer binding of the same name.
    private static func localBinding(named name: String, in scope: Syntax, enclosing child: Syntax) -> InspectionBinding? {
        if let bindingList = scope.as(PatternBindingListSyntax.self) {
            return Array(bindingList).filter { $0.position < child.position }
                .flatMap { variableBindings($0) }.last { $0.0 == name }?.1
        }
        if let forStmt = scope.as(ForStmtSyntax.self), child.id == forStmt.body.id {
            if identifier(of: forStmt.pattern) == name { return .element(forStmt.sequence) }
            return boundNames(in: forStmt.pattern).contains(name) ? .opaque : nil
        }
        return patternScopeBinding(named: name, in: scope)
    }

    private static func patternScopeBinding(named name: String, in scope: Syntax) -> InspectionBinding? {
        if let switchCase = scope.as(SwitchCaseSyntax.self), case .case(let label) = switchCase.label {
            let names = label.caseItems.flatMap { boundNames(in: $0.pattern) }
            return names.contains(name) ? .opaque : nil
        }
        if let catchClause = scope.as(CatchClauseSyntax.self) {
            let names = catchClause.catchItems.flatMap { item in item.pattern.map(boundNames) ?? [] }
            let implicitError = catchClause.catchItems.isEmpty && name == "error"
            return names.contains(name) || implicitError ? .opaque : nil
        }
        return nil
    }

    private static func conditionBindings(_ element: ConditionElementSyntax) -> [(String, InspectionBinding)] {
        switch element.condition {
        case .optionalBinding(let optional):
            // `if let (a, b) = pair` binds names the rule cannot read, shadowing outer ones.
            guard let name = identifier(of: optional.pattern) else {
                return boundNames(in: optional.pattern).map { ($0, .opaque) }
            }
            // A shorthand `if let x` rebinds the outer `x`, so it binds nothing new here.
            guard let value = optional.initializer?.value else { return [] }
            return [(name, .value(value, annotation: optional.typeAnnotation?.type))]

        case .matchingPattern(let matching):
            return boundNames(in: matching.pattern).map { ($0, .opaque) }

        default:
            return []
        }
    }
}

/// A closure ViewInspector calls with the inspected view: `sut.inspect { view in … }`,
/// `sut.inspection.inspect(after:) { view in … }`, `sut.on(\.didAppear) { view in … }`. A
/// predicate passed to `find` is not one — its parameter is a candidate, not a root.
struct InspectionRelay {
    /// The view being inspected — `sut` in all three spellings above.
    let subject: ExprSyntax?

    /// `View.inspect(function:file:line:inspection:)` and the emissary's
    /// `inspect(after:onReceive:function:file:line:_:)`.
    private static let relayLabels: Set<String> = ["after", "onReceive", "function", "file", "line", "inspection"]

    init?(_ closure: ClosureExprSyntax) {
        guard let call = Self.enclosingCall(of: closure),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self) else {
            return nil
        }
        switch member.declName.baseName.text {
        case "inspect":
            let labels = call.arguments.compactMap { $0.label?.text }
            guard labels.allSatisfy(Self.relayLabels.contains) else { return nil }

        case "on":
            guard call.arguments.first?.expression.is(KeyPathExprSyntax.self) == true else { return nil }

        default:
            return nil
        }
        // `sut.inspection.inspect { }` inspects `sut`; the emissary is only the relay. It may be
        // optional: `sut.inspection?.inspect { }`.
        let base = member.base.map(InspectionChainEvaluator.unwrapped)
        if let emissary = base?.as(MemberAccessExprSyntax.self), emissary.declName.baseName.text == "inspection" {
            subject = emissary.base
        } else {
            subject = base
        }
    }

    static func enclosingCall(of closure: ClosureExprSyntax) -> FunctionCallExprSyntax? {
        var node = closure.parent
        while let current = node {
            if let call = current.as(FunctionCallExprSyntax.self) { return call }
            let passesThrough = current.is(LabeledExprSyntax.self)
                || current.is(LabeledExprListSyntax.self)
                || current.is(MultipleTrailingClosureElementSyntax.self)
                || current.is(MultipleTrailingClosureElementListSyntax.self)
            guard passesThrough else { return nil }
            node = current.parent
        }
        return nil
    }
}

/// Reads a type annotation as `InspectableView<ViewType.X>`, through `?`, `!` and a module
/// qualifier. A closure, dictionary or array type that merely mentions one is not one.
struct InspectableViewType {
    let isInspectableView: Bool
    /// What a step on a value of this type does; see `ReceiverKind`.
    let kind: ReceiverKind
    /// `X` in `InspectableView<ViewType.X>`, spelled as its accessor: `ForEach` → `forEach`.
    let viewType: String?
    /// `T` in `InspectableView<ViewType.View<T>>`: the view whose layout is walked.
    let subjectType: String?
    /// A variadic parameter of this type: an array of such views, in the order they were passed.
    var isArgumentList = false
    /// Spelled `InspectableView<…>?` or `InspectableView<…>!`.
    let isOptional: Bool

    init(_ type: TypeSyntax) {
        isOptional = InspectionBindingResolver.isOptionalType(type)
        let current = Self.unwrapped(type)
        let generics: GenericArgumentClauseSyntax?
        if let identifier = current.as(IdentifierTypeSyntax.self), identifier.name.text == "InspectableView" {
            generics = identifier.genericArgumentClause
        } else if let member = current.as(MemberTypeSyntax.self), member.name.text == "InspectableView" {
            generics = member.genericArgumentClause
        } else {
            (isInspectableView, kind, viewType, subjectType) = (false, .typed, nil, nil)
            return
        }
        isInspectableView = true
        let argument = generics?.arguments.first?.argument.trimmedDescription ?? ""
        (kind, viewType, subjectType) = Self.read(viewTypeArgument: argument)
    }

    /// Through `?`, `!`, `Optional<…>`, `inout` and parentheses.
    static func unwrapped(_ type: TypeSyntax) -> TypeSyntax {
        var current = type
        while true {
            if let optional = current.as(OptionalTypeSyntax.self) {
                current = optional.wrappedType
            } else if let forced = current.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
                current = forced.wrappedType
            } else if let attributed = current.as(AttributedTypeSyntax.self) {
                current = attributed.baseType
            } else if let tuple = current.as(TupleTypeSyntax.self), tuple.elements.count == 1,
                      let only = tuple.elements.first {
                current = only.type
            } else if let identifier = current.as(IdentifierTypeSyntax.self), identifier.name.text == "Optional",
                      let wrapped = identifier.genericArgumentClause?.arguments.first?.argument.as(TypeSyntax.self) {
                current = wrapped
            } else {
                return current
            }
        }
    }

    /// `ViewType.ClassifiedView` is a found view; `ViewType.View<T>` and `ViewType.ViewModifier<T>`
    /// have `T`'s body's views as children; `ViewType.X` is a SwiftUI view; anything else — a
    /// generic `V` — is unknown, and read as a SwiftUI view.
    static func read(viewTypeArgument text: String) -> (ReceiverKind, String?, String?) {
        let unqualified = text.hasPrefix("ViewInspector.") ? String(text.dropFirst("ViewInspector.".count)) : text
        guard unqualified.hasPrefix("ViewType.") else { return (.typed, nil, nil) }
        let name = String(unqualified.dropFirst("ViewType.".count))
        if name == "ClassifiedView" || name == "ParentView" {
            return (.found, nil, nil)
        }
        for wrapper in ["View<", "ViewModifier<"] where name.hasPrefix(wrapper) && name.hasSuffix(">") {
            let subject = name.dropFirst(wrapper.count).dropLast()
            return (.content, nil, InspectionVocabulary.typeName(String(subject)))
        }
        return (.typed, InspectionVocabulary.accessorName(forViewType: name), nil)
    }
}

/// The member lists of every type declaration and extension in a file, by the type's name.
private final class TypeMemberLists: SyntaxVisitor {
    private(set) var lists: [String: [MemberBlockItemListSyntax]] = [:]

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        lists[node.name.text, default: []].append(node.memberBlock.members)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        lists[node.name.text, default: []].append(node.memberBlock.members)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        lists[node.name.text, default: []].append(node.memberBlock.members)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        lists[node.name.text, default: []].append(node.memberBlock.members)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = InspectionVocabulary.typeName(node.extendedType.trimmedDescription)
        lists[name, default: []].append(node.memberBlock.members)
        return .visitChildren
    }
}

/// The declared return type of every function in a file, by name, with the type declaring it.
private final class FunctionReturnTypes: SyntaxVisitor {
    struct Declaration {
        /// The innermost type or extension around the function; `nil` at file scope.
        let owner: String?
        let returnType: String
    }

    private(set) var declarations: [String: [Declaration]] = [:]

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let returned = node.signature.returnClause?.type {
            let spelled = InspectableViewType.unwrapped(returned).trimmedDescription
            let owner = InspectionChainEvaluator.enclosingTypeNames(of: Syntax(node)).first
            // `static func make() -> Self` builds its own type.
            let returnType = spelled == "Self" ? owner ?? spelled : InspectionVocabulary.typeName(spelled)
            declarations[node.name.text, default: []].append(Declaration(owner: owner, returnType: returnType))
        }
        return .visitChildren
    }
}
