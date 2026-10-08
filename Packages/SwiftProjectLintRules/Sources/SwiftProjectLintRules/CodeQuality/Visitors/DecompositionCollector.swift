import SwiftSyntax

/// Where a decomposing member puts a field: a storage **key** (`forKey: "identifier"`,
/// `record["identifier"] = …`, `.identifier` in a coder), or a **property** (`self.name = draft.name`,
/// or a mirrored `entity.name = draft.name`).
///
/// A slot is the evidence that two members of one type form a round trip. The member that rebuilds
/// the value must read a slot the decomposing member wrote — the same key, or the same property —
/// or the pair is not a round trip at all, just two members that happen to mention one type.
enum RoundTripSlot: Hashable {
    case key(String)
    case property(String)

    /// A storage key: a non-empty string literal, or a `.member` / `Keys.member` constant.
    static func key(of expression: ExprSyntax) -> String? {
        if let string = expression.as(StringLiteralExprSyntax.self),
           string.segments.count == 1,
           let text = string.segments.first?.as(StringSegmentSyntax.self)?.content.text,
           text.isEmpty == false {
            return text
        }
        guard let member = expression.as(MemberAccessExprSyntax.self) else { return nil }
        guard let base = member.base else { return "." + member.declName.baseName.text }
        // `Keys.identifier` names a constant; `record.identifier` reads a value and is not a key.
        guard let reference = base.as(DeclReferenceExprSyntax.self),
              reference.baseName.text.first?.isUppercase == true else { return nil }
        return member.trimmedDescription
    }
}

/// What one member does with its parameter of domain type `T`: which fields it stores, and where.
///
///     func save(_ order: Order) {
///         record.setValue(order.identifier, forKey: "identifier")   // key "identifier" ← identifier
///         record.setValue(order.paymentMethod.rawValue, forKey: "paymentMethod")
///     }
///
/// A member that hands the parameter on **whole** — `orders.append(order)`, `encode(order)`,
/// `cache[id] = order` — keeps every field by construction, so it is not a decomposition and the
/// collector reports `storesWhole`. That is the in-memory store every test suite has, and it must
/// never pair with anything.
final class DecompositionCollector: SyntaxVisitor {

    /// Field names stored, keyed by the slot they went into.
    private(set) var slots: [RoundTripSlot: Set<String>] = [:]

    /// The parameter itself was passed, returned, or assigned as one value.
    private(set) var storesWhole = false

    private let parameters: Set<String>
    private var loopVariables: Set<String> = []
    private var localNames: Set<String> = []

    /// Locals that carry fields — `let encoded = try encoder.encode(order.items)` carries `items`
    /// to wherever `encoded` is stored next.
    private var aliases: [String: Set<String>] = [:]

    init(parameters: Set<String>) {
        self.parameters = parameters
        super.init(viewMode: .sourceAccurate)
    }

    /// The fields of the parameter an expression reads, directly or through an alias.
    func fields(in node: some SyntaxProtocol) -> Set<String> {
        let finder = FieldReadFinder(values: parameters.union(loopVariables), aliases: aliases)
        finder.walk(Syntax(node))
        return finder.fields
    }

    // MARK: - Bindings

    /// `for order in orders` — an array parameter decomposed one element at a time.
    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        if let sequence = node.sequence.as(DeclReferenceExprSyntax.self),
           parameters.contains(sequence.baseName.text),
           let element = node.pattern.as(IdentifierPatternSyntax.self) {
            loopVariables.insert(element.identifier.text)
        }
        return .visitChildren
    }

    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        bind(node.pattern, to: node.initializer?.value)
        return .visitChildren
    }

    override func visit(_ node: OptionalBindingConditionSyntax) -> SyntaxVisitorContinueKind {
        bind(node.pattern, to: node.initializer?.value)
        return .visitChildren
    }

    private func bind(_ pattern: PatternSyntax, to value: ExprSyntax?) {
        guard let name = pattern.as(IdentifierPatternSyntax.self)?.identifier.text else { return }
        localNames.insert(name)
        guard let value else { return }
        let carried = fields(in: value)
        if carried.isEmpty == false { aliases[name, default: []].formUnion(carried) }
    }

    // MARK: - Stores

    /// `name = draft.name`, `self.name = …`, `entity.name = draft.name`, `record["name"] = …`.
    ///
    /// `Parser.parse` leaves operators unfolded, so an assignment is a `SequenceExprSyntax` whose
    /// second element is the `=`.
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Array(node.elements)
        guard elements.count >= 3, elements[1].is(AssignmentExprSyntax.self) else { return .visitChildren }
        let carried = elements.dropFirst(2).reduce(into: Set<String>()) { $0.formUnion(fields(in: $1)) }
        guard carried.isEmpty == false else { return .visitChildren }
        for slot in slots(assignedBy: elements[0], carrying: carried) {
            slots[slot, default: []].formUnion(carried)
        }
        return .visitChildren
    }

    private func slots(assignedBy target: ExprSyntax, carrying carried: Set<String>) -> [RoundTripSlot] {
        if let reference = target.as(DeclReferenceExprSyntax.self) {
            // A bare name is `self.name` — unless the member declared a local by that name.
            let name = reference.baseName.text
            return localNames.contains(name) ? [] : [.property(name)]
        }
        if let member = target.as(MemberAccessExprSyntax.self) {
            let name = member.declName.baseName.text
            let ontoSelf = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "self"
            // `entity.name = draft.name` is a mapping only when the names mirror. Without that, an
            // assignment into any other object's property — `label.text = order.title` — would be
            // mistaken for storage.
            return ontoSelf || carried.contains(name) ? [.property(name)] : []
        }
        if let subscriptCall = target.as(SubscriptCallExprSyntax.self) {
            return subscriptCall.arguments.compactMap { RoundTripSlot.key(of: $0.expression).map(RoundTripSlot.key) }
        }
        return []
    }

    /// `record.setValue(order.identifier, forKey: "identifier")`, `defaults.set(…, forKey: Keys.name)`,
    /// `container.encode(order.name, forKey: .name)`.
    ///
    /// Only an argument **labelled** as a key counts. Any other literal beside a field read is just
    /// a literal: `Status(name: source.name, displayName: "Swift Evolution")` is a constructor, and
    /// treating `"Swift Evolution"` as a storage key paired it with an unrelated member that showed
    /// the same title.
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        var keys: [String] = []
        var values: [ExprSyntax] = []
        for argument in node.arguments {
            if let label = argument.label?.text, label.lowercased().contains("key"),
               let key = RoundTripSlot.key(of: argument.expression) {
                keys.append(key)
            } else {
                values.append(argument.expression)
            }
        }
        // Most calls have no key, and only a keyed call can store anything — so the argument
        // subtrees are searched for fields only then, not once per enclosing call.
        guard keys.isEmpty == false else { return .visitChildren }
        let carried = values.reduce(into: Set<String>()) { $0.formUnion(fields(in: $1)) }
        guard carried.isEmpty == false else { return .visitChildren }
        for key in keys {
            slots[.key(key), default: []].formUnion(carried)
        }
        return .visitChildren
    }

    // MARK: - Whole-value use

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.baseName.text
        if parameters.contains(name) || loopVariables.contains(name), Self.isWholeValueUse(node) {
            storesWhole = true
        }
        return .visitChildren
    }

    /// The value used as itself: a call argument, an array element, a `return`, or the whole of an
    /// assignment's right-hand side. Reading `order.id`, testing `order != nil`, and rebinding with
    /// `guard let order` all leave it in pieces.
    private static func isWholeValueUse(_ node: DeclReferenceExprSyntax) -> Bool {
        // `try order`, `await order`, `order!` are still the whole value.
        var value = Syntax(node)
        while let wrapper = value.parent, isTransparentWrapper(wrapper) {
            value = wrapper
        }
        guard let parent = value.parent else { return false }
        if parent.is(LabeledExprSyntax.self) {
            return parent.parent?.parent?.is(TupleExprSyntax.self) == false
        }
        if parent.is(ArrayElementSyntax.self) || parent.is(ReturnStmtSyntax.self) {
            return true
        }
        return isAssignedWhole(value, within: parent)
    }

    private static func isTransparentWrapper(_ syntax: Syntax) -> Bool {
        syntax.is(TryExprSyntax.self) || syntax.is(AwaitExprSyntax.self) || syntax.is(ForceUnwrapExprSyntax.self)
    }

    private static func isAssignedWhole(_ value: Syntax, within parent: Syntax) -> Bool {
        guard let sequence = parent.as(ExprListSyntax.self)?.parent?.as(SequenceExprSyntax.self) else { return false }
        let elements = Array(sequence.elements)
        return elements.count == 3
            && elements[1].is(AssignmentExprSyntax.self)
            && Syntax(elements[2]).id == value.id
    }
}

/// The fields of the given values an expression reads — `order.items`, `order.discount?.value` —
/// plus whatever fields aliases of them carry.
private final class FieldReadFinder: SyntaxVisitor {

    private(set) var fields: Set<String> = []
    private let values: Set<String>
    private let aliases: [String: Set<String>]

    init(values: Set<String>, aliases: [String: Set<String>]) {
        self.values = values
        self.aliases = aliases
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.baseName.text
        if values.contains(name),
           let member = node.parent?.as(MemberAccessExprSyntax.self),
           member.base?.id == ExprSyntax(node).id {
            fields.insert(member.declName.baseName.text)
        } else if let carried = aliases[name] {
            fields.formUnion(carried)
        }
        return .visitChildren
    }
}

/// Every slot a member reads: the string-literal and constant keys it mentions, and every name it
/// references — the properties a rebuild reads back.
final class SlotReadCollector: SyntaxVisitor {

    private(set) var slots: Set<RoundTripSlot> = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        if let key = RoundTripSlot.key(of: ExprSyntax(node)) { slots.insert(.key(key)) }
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if let key = RoundTripSlot.key(of: ExprSyntax(node)) { slots.insert(.key(key)) }
        slots.insert(.property(node.declName.baseName.text))
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        slots.insert(.property(node.baseName.text))
        return .visitChildren
    }
}

/// Every `T(…)` or `T.init(…)` in a member, for the domain types of interest.
final class DomainConstructionFinder: SyntaxVisitor {

    private(set) var constructions: [(type: String, call: FunctionCallExprSyntax)] = []
    private let domainTypes: Set<String>

    init(domainTypes: Set<String>) {
        self.domainTypes = domainTypes
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let type = Self.constructedType(of: node), domainTypes.contains(type) {
            constructions.append((type, node))
        }
        return .visitChildren
    }

    private static func constructedType(of call: FunctionCallExprSyntax) -> String? {
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        guard let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "init" else { return nil }
        return member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text
    }
}
