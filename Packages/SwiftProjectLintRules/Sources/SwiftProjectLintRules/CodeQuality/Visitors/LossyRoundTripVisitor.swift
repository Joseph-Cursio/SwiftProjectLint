import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// A type that takes a value apart into storage and puts it back together — and hard-codes an
/// **empty** value for a field on the way back, so that field never survives the round trip.
///
///     func save(_ order: Order) async throws {
///         record.setValue(order.identifier, forKey: "identifier")
///         record.setValue(order.paymentMethod.rawValue, forKey: "paymentMethod")
///     }
///
///     func recentOrders() async throws -> [Order] {
///         …
///         let identifier = record.value(forKey: "identifier") as? UUID
///         …
///         return Order(identifier: identifier, items: [], paymentMethod: method, discount: nil)
///     }
///
/// Every order comes back with no line items and no discount. It compiles, it satisfies the store's
/// protocol, and the in-memory test double every suite has round-trips whole values — so the tests
/// pass against the fake while the app loses data against the real store. `Lossy Struct Rebuild`
/// cannot see it: the order is built from a Core Data record, not copied from another `Order`.
///
/// ## What makes it a round trip, and not two members that mention one type
///
/// The rule needs evidence that the two members are halves of one round trip, and the evidence is a
/// **shared slot**. The decomposing member stores fields of its `T` parameter somewhere — under a
/// key (`forKey: "identifier"`), or in a property (`self.name = draft.name`) — and the rebuilding
/// member reads at least one of those same slots back. Without that, `func select(_ order: Order)`
/// and `func makeDraft() -> Order` would pair on type alone, and on the first measurement — a gate
/// of "any member that reads a field off a `T` parameter" — 21 of 23 production findings were that
/// kind of noise.
///
/// ## Not reported
///
/// - **A constructed type the project does not declare** (`knownLocalTypeNames`). `IndexPath(row:
///   selectedIndex, section: 0)` after storing `indexPath.row` is a genuine round trip that drops a
///   field — deliberately, because the table has one section. Every such finding on a 48,000-file
///   held-out corpus was a framework or dependency type, and every one was intended.
/// - **A member that keeps the value whole** — `orders.append(order)`, `encode(order)`,
///   `cache[id] = order`. Nothing is decomposed, so nothing can be dropped.
/// - **A construction made only of literals.** `Order(identifier: UUID(), items: [])` with no slot
///   read in its arguments is a fresh value or a fallback, not a rebuild.
/// - **Test and fixture files**, where partial values are the point.
///
/// ## Accepted gaps
///
/// - The two halves must be in one file — the type's body and its same-file extensions. A store
///   whose save and load live in different files' extensions is not paired.
/// - Only the literal empties `[]`, `[:]`, `nil`, `""`, `0` and `0.0` count. `false`, `.none` and
///   non-empty constants (`minSwiftVersion: "6.0"`) are left alone: they are as often a correct
///   default as a lost field.
/// - A field the initialiser defaults and the rebuild simply omits is not seen. That is
///   `Lossy Struct Rebuild`'s shape, from the other side.
///
/// `warning`, on by default: the data loss is not latent, it happens on every load.
final class LossyRoundTripVisitor: BasePatternVisitor {

    private var fileIsTestOrFixture = false

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        fileIsTestOrFixture = isTestOrFixtureFile()
    }

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        guard fileIsTestOrFixture == false else { return .skipChildren }
        let grouping = MemberGrouping(viewMode: .sourceAccurate)
        grouping.walk(node)
        for owner in grouping.owners {
            for rebuild in lossyRebuilds(in: owner) {
                report(rebuild)
            }
        }
        return .skipChildren
    }

    // MARK: - Analysis

    /// Every rebuild in `owner` that hard-codes an empty value for a field of a value `owner`
    /// decomposes elsewhere.
    private func lossyRebuilds(in owner: MemberGrouping.Owner) -> [LossyRebuild] {
        let decompositions = decompositions(in: owner)
        guard decompositions.isEmpty == false else { return [] }

        var rebuilds: [LossyRebuild] = []
        for member in owner.members {
            guard let body = Self.body(of: member) else { continue }
            let finder = DomainConstructionFinder(domainTypes: Set(decompositions.keys))
            finder.walk(body)
            guard finder.constructions.isEmpty == false else { continue }
            let reads = SlotReadCollector()
            reads.walk(body)
            for (type, call) in finder.constructions {
                // A member that takes `T` apart is one half of the round trip, never the other.
                guard let decomposition = decompositions[type],
                      decomposition.members.contains(where: { $0.id == member.id }) == false,
                      decomposition.slots.keys.contains(where: reads.slots.contains),
                      let rebuild = LossyRebuild(call: call, type: type, reader: member, decomposition: decomposition)
                else { continue }
                rebuilds.append(rebuild)
            }
        }
        return rebuilds
    }

    /// Per project-declared domain type, what `owner`'s members store of it and where.
    private func decompositions(in owner: MemberGrouping.Owner) -> [String: Decomposition] {
        var result: [String: Decomposition] = [:]
        for member in owner.members {
            guard let body = Self.body(of: member) else { continue }
            for (type, names) in domainParameters(of: member, excluding: owner.name) {
                let collector = DecompositionCollector(parameters: names)
                collector.walk(body)
                guard collector.slots.isEmpty == false, collector.storesWhole == false else { continue }
                result[type, default: Decomposition()].absorb(collector.slots, from: member)
            }
        }
        return result
    }

    /// The member's parameters typed as a project-declared type — `T`, `T?` or `[T]` — grouped by
    /// type. `inout` parameters are mutated in place, not taken apart, and are skipped.
    private func domainParameters(of member: DeclSyntax, excluding owner: String) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for parameter in Self.parameters(of: member) {
            if let attributed = parameter.type.as(AttributedTypeSyntax.self),
               attributed.specifiers.contains(where: { $0.trimmedDescription == "inout" }) {
                continue
            }
            guard let type = Self.domainTypeName(parameter.type),
                  type != owner,
                  knownLocalTypeNames.contains(type) else { continue }
            result[type, default: []].insert(parameter.secondName?.text ?? parameter.firstName.text)
        }
        return result
    }

    // MARK: - Reporting

    private func report(_ rebuild: LossyRebuild) {
        let call = Syntax(rebuild.call)
        addIssue(
            severity: .warning,
            message: rebuild.message,
            filePath: getFilePath(for: call),
            lineNumber: getLineNumber(for: call),
            suggestion: "Store every stored field `\(rebuild.type)` has and read each one back. If a "
                + "field is deliberately not persisted, make that visible — an optional with a comment "
                + "saying so — because a reader cannot tell a choice from a mistake. A save-then-load "
                + "property test (`load(save(x)) == x`) catches this class at runtime.",
            ruleName: .lossyRoundTrip,
            symbol: rebuild.type
        )
    }

    // MARK: - Syntax helpers

    static func body(of member: DeclSyntax) -> Syntax? {
        if let function = member.as(FunctionDeclSyntax.self) { return function.body.map(Syntax.init) }
        if let initializer = member.as(InitializerDeclSyntax.self) { return initializer.body.map(Syntax.init) }
        if let variable = member.as(VariableDeclSyntax.self) {
            return variable.bindings.first?.accessorBlock.map(Syntax.init)
        }
        return nil
    }

    static func parameters(of member: DeclSyntax) -> [FunctionParameterSyntax] {
        if let function = member.as(FunctionDeclSyntax.self) {
            return Array(function.signature.parameterClause.parameters)
        }
        if let initializer = member.as(InitializerDeclSyntax.self) {
            return Array(initializer.signature.parameterClause.parameters)
        }
        return []
    }

    /// `Order`, `Order?`, `[Order]`, `some Order` → `"Order"`. Generic and composite types → `nil`.
    static func domainTypeName(_ type: TypeSyntax) -> String? {
        var current = type
        while true {
            if let attributed = current.as(AttributedTypeSyntax.self) {
                current = attributed.baseType
            } else if let optional = current.as(OptionalTypeSyntax.self) {
                current = optional.wrappedType
            } else if let unwrapped = current.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
                current = unwrapped.wrappedType
            } else if let array = current.as(ArrayTypeSyntax.self) {
                current = array.element
            } else if let opaque = current.as(SomeOrAnyTypeSyntax.self) {
                current = opaque.constraint
            } else {
                break
            }
        }
        if let identifier = current.as(IdentifierTypeSyntax.self), identifier.genericArgumentClause == nil {
            return identifier.name.text
        }
        return current.as(MemberTypeSyntax.self)?.name.text
    }

    /// `save(_:)`, `init(editing:)`, `recentOrders()` — how a member is named in a message.
    static func displayName(of member: DeclSyntax) -> String {
        let labels = parameters(of: member).map { "\($0.firstName.text):" }.joined()
        if let function = member.as(FunctionDeclSyntax.self) { return "\(function.name.text)(\(labels))" }
        if member.is(InitializerDeclSyntax.self) { return "init(\(labels))" }
        let binding = member.as(VariableDeclSyntax.self)?.bindings.first
        return binding?.pattern.trimmedDescription ?? "this member"
    }
}

/// What a type's members store of one domain type, merged across every member that decomposes it.
struct Decomposition {
    var slots: [RoundTripSlot: Set<String>] = [:]
    var members: [DeclSyntax] = []

    /// Every field stored anywhere.
    var storedFields: Set<String> { slots.values.reduce(into: []) { $0.formUnion($1) } }

    mutating func absorb(_ newSlots: [RoundTripSlot: Set<String>], from member: DeclSyntax) {
        slots.merge(newSlots) { $0.union($1) }
        members.append(member)
    }
}

/// One rebuild that hard-codes empty values for fields of a round-tripped type.
struct LossyRebuild {

    /// A field the rebuild sets to an empty literal, and whether the decomposing member had stored it.
    struct DroppedField {
        let label: String
        let literal: String
        let wasStored: Bool

        var name: String { "`\(label)`" }
        var rendered: String { "`\(label): \(literal)`" }
    }

    let call: FunctionCallExprSyntax
    let type: String
    let readerName: String
    let writerNames: [String]
    let dropped: [DroppedField]

    /// `nil` unless the call hard-codes at least one empty value **and** reads something — a
    /// construction made only of literals is a fresh value or a fallback, not a rebuild.
    init?(call: FunctionCallExprSyntax, type: String, reader: DeclSyntax, decomposition: Decomposition) {
        var dropped: [DroppedField] = []
        var readsSomething = false
        for argument in call.arguments {
            if let literal = EmptyLiteral.text(of: argument.expression) {
                guard let label = argument.label?.text else { continue }
                dropped.append(DroppedField(
                    label: label, literal: literal, wasStored: decomposition.storedFields.contains(label)
                ))
            } else if EmptyLiteral.isConstant(argument.expression) == false {
                readsSomething = true
            }
        }
        guard dropped.isEmpty == false, readsSomething else { return nil }
        self.call = call
        self.type = type
        self.readerName = LossyRoundTripVisitor.displayName(of: reader)
        self.writerNames = decomposition.members.map(LossyRoundTripVisitor.displayName(of:))
        self.dropped = dropped
    }

    /// Names the halves of the round trip, and splits the fields by how they are lost — never
    /// stored, or stored and then thrown away on the way back, which is the stronger claim.
    var message: String {
        let writers = writerNames.map { "`\($0)`" }.joined(separator: " / ")
        let neverStored = dropped.filter { $0.wasStored == false }
        let discarded = dropped.filter(\.wasStored)
        var clauses: [String] = []
        if neverStored.isEmpty == false {
            clauses.append("\(writers) never stores \(Self.list(neverStored.map(\.name), conjunction: "or")), "
                + "and `\(readerName)` rebuilds it with \(neverStored.map(\.rendered).joined(separator: ", "))")
        }
        if discarded.isEmpty == false {
            clauses.append("\(writers) stores \(Self.list(discarded.map(\.name), conjunction: "and")), but "
                + "`\(readerName)` throws \(discarded.count == 1 ? "it" : "them") away: "
                + discarded.map(\.rendered).joined(separator: ", "))
        }
        let fields = dropped.count == 1 ? "that field" : "those fields"
        return "`\(type)` does not survive its round trip: " + clauses.joined(separator: "; ")
            + ". Every value comes back without \(fields), silently."
    }

    private static func list(_ items: [String], conjunction: String) -> String {
        guard let last = items.last else { return "" }
        return items.count == 1 ? last : items.dropLast().joined(separator: ", ") + " \(conjunction) " + last
    }
}

/// The literal empties a rebuild can hard-code for a field it did not read back.
enum EmptyLiteral {

    /// `[]`, `[:]`, `nil`, `""`, `0`, `0.0` — rendered as written; `nil` for anything else.
    static func text(of expression: ExprSyntax) -> String? {
        if let array = expression.as(ArrayExprSyntax.self), array.elements.isEmpty { return "[]" }
        if let dictionary = expression.as(DictionaryExprSyntax.self), dictionary.content.is(TokenSyntax.self) {
            return "[:]"
        }
        if expression.is(NilLiteralExprSyntax.self) { return "nil" }
        if let string = expression.as(StringLiteralExprSyntax.self),
           string.segments.allSatisfy({ $0.as(StringSegmentSyntax.self)?.content.text.isEmpty ?? false }) {
            return "\"\""
        }
        if let integer = expression.as(IntegerLiteralExprSyntax.self), integer.literal.text == "0" { return "0" }
        if let float = expression.as(FloatLiteralExprSyntax.self), Double(float.literal.text) == 0 {
            return float.literal.text
        }
        return nil
    }

    /// A value fixed in the source — a literal, a negated literal, or a bare `.enumCase` — which reads
    /// nothing back from storage.
    static func isConstant(_ expression: ExprSyntax) -> Bool {
        if expression.is(ArrayExprSyntax.self) || expression.is(DictionaryExprSyntax.self)
            || expression.is(NilLiteralExprSyntax.self) || expression.is(StringLiteralExprSyntax.self)
            || expression.is(IntegerLiteralExprSyntax.self) || expression.is(FloatLiteralExprSyntax.self)
            || expression.is(BooleanLiteralExprSyntax.self) {
            return true
        }
        if let prefix = expression.as(PrefixOperatorExprSyntax.self) {
            return isConstant(prefix.expression)
        }
        if let member = expression.as(MemberAccessExprSyntax.self) {
            return member.base == nil
        }
        return false
    }
}

/// Each type's functions, initialisers and computed properties, with its same-file extensions merged
/// in, in the order the types first appear.
final class MemberGrouping: SyntaxVisitor {

    struct Owner {
        let name: String
        var members: [DeclSyntax]
    }

    private(set) var owners: [Owner] = []
    private var index: [String: Int] = [:]

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        add(node.name.text, node.memberBlock)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        add(node.name.text, node.memberBlock)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        add(node.name.text, node.memberBlock)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        add(node.name.text, node.memberBlock)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        add(node.extendedType.trimmedDescription, node.memberBlock)
        return .visitChildren
    }

    private func add(_ name: String, _ block: MemberBlockSyntax) {
        let members = block.members.map(\.decl).filter(Self.isAnalysable)
        if let position = index[name] {
            owners[position].members.append(contentsOf: members)
        } else {
            index[name] = owners.count
            owners.append(Owner(name: name, members: members))
        }
    }

    private static func isAnalysable(_ decl: DeclSyntax) -> Bool {
        if decl.is(FunctionDeclSyntax.self) || decl.is(InitializerDeclSyntax.self) { return true }
        return decl.as(VariableDeclSyntax.self)?.bindings.first?.accessorBlock != nil
    }
}
