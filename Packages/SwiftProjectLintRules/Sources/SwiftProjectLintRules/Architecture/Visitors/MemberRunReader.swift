import SwiftSyntax

/// Reading a **member run** out of source — one operation applied, member by member, to a run of
/// one value's stored members — for `ParallelListDrift`'s fourth carrier.
///
///     if validationErrors.isEmpty
///         && parsedConfig.rules.isEmpty
///         && parsedConfig.disabledRules == nil
///         && parsedConfig.optInRules == nil
///         && parsedConfig.onlyRules == nil { … }          // ← `analyzerRules` forgotten
///
/// A run like this is an enumeration of a type's members transcribed by hand, and it drifts the
/// way any other hand-kept list does. The condition above is SwiftLintRuleStudio's import
/// validation: two other functions in the same module enumerate the config's rule lists *with*
/// `analyzerRules`, so a config defining only analyzer rules was warned "Configuration appears
/// empty – no rules defined." Mutation testing found it — all four `&&` mutants survived — and no
/// existing carrier could, because nothing in it is an enum, an array of names or a registration
/// call.
///
/// Three shapes carry a run, each read only where the *same* operation is applied to each member:
///
/// - **a logical chain** — operands of one connective (`&&` or `||`) or of one condition list, each
///   reading exactly one member of the value;
/// - **a statement run** — consecutive statements identical but for the member they read and the
///   names they bind (`if let x = config.optInRules { ids.formUnion(x) }`, ×4). The statement just
///   before and just after the run is absorbed when it reads exactly one member of the same value:
///   `var ids = Set(config.rules.keys)` seeds the accumulator the run then fills, and leaving it out
///   would make the complete enumeration look like it is missing `rules`;
/// - **an array of member reads** — `[config.disabledRules, config.optInRules, …]`.
///
/// A member is a property read off a lowercase identifier: `self` and type names are excluded (an
/// initialiser's `self.a = a` run is not an enumeration, and `Foo.bar` is a static), and so is a
/// method call (`view.layout()` names an action, not a member). So is a member that is only
/// *assigned*: `label.isBezeled = false; label.isEditable = false` configures a value, and a run of
/// it, measured over 40 repositories, is view setup rather than an enumeration of anything.
enum MemberRunReader {

    /// A run: the value read, the members read off it, and where.
    ///
    /// `core` is the members read by the *same* operation — the operands of one shape, or the
    /// statements of the run proper. The rest were read beside them: `parsedConfig.rules.isEmpty`
    /// beside three `== nil` checks, or `var ids = Set(config.rules.keys)` before the run it
    /// seeds. A member is reported missing only from a counterpart's core, because that is what
    /// was enumerated; a member read alongside is often a different condition entirely.
    struct Run {
        let base: String
        let members: [String]
        let core: Set<String>
        let node: Syntax
    }

    /// The fewest distinct members a run must read — the same floor `ParallelListDrift` applies to
    /// every list.
    static let minMembers = 3

    // MARK: - Logical chains

    /// The runs in one flat `&&` or `||` chain.
    ///
    /// `SwiftParser` leaves operators unfolded, so `a.x == nil && a.y == nil` is one sequence of
    /// seven elements. Splitting it at the connective is sound because every operator that binds
    /// looser than `&&` — `||` itself, `?:`, assignment — disqualifies the sequence first, and a
    /// chain mixing `&&` with `||` is not one operation applied uniformly.
    static func runs(inLogicalChain node: SequenceExprSyntax) -> [Run] {
        var connectives: Set<String> = []
        var operands: [[Syntax]] = [[]]
        for element in node.elements {
            if element.is(UnresolvedTernaryExprSyntax.self) || element.is(AssignmentExprSyntax.self) {
                return []
            }
            if let connective = element.as(BinaryOperatorExprSyntax.self),
               ["&&", "||"].contains(connective.operator.text) {
                connectives.insert(connective.operator.text)
                operands.append([])
            } else {
                operands[operands.count - 1].append(Syntax(element))
            }
        }
        guard connectives.count == 1 else { return [] }
        return runs(overOperands: operands, node: Syntax(node))
    }

    /// The runs in a condition list — `guard a.x != nil, a.y != nil, a.z != nil`.
    static func runs(inConditions node: ConditionElementListSyntax) -> [Run] {
        runs(overOperands: node.map { [Syntax($0)] }, node: Syntax(node))
    }

    /// For each value, the members read by operands that read exactly one member of it, and the
    /// largest set of them whose operands share one shape.
    private static func runs(overOperands operands: [[Syntax]], node: Syntax) -> [Run] {
        guard operands.count >= minMembers else { return [] }
        var membersByBase: [String: [String]] = [:]
        var membersByShape: [String: [String: Set<String>]] = [:]
        for operand in operands {
            for (base, members) in reads(in: operand) where members.count == 1 {
                membersByBase[base, default: []].append(contentsOf: members)
                membersByShape[base, default: [:]][shape(of: operand, base: base), default: []]
                    .formUnion(members)
            }
        }
        let cores = membersByShape.mapValues { shapes in
            shapes.values.max {
                ($0.count, $0.sorted().joined(separator: ",")) < ($1.count, $1.sorted().joined(separator: ","))
            } ?? []
        }
        return sortedRuns(membersByBase, cores: cores, node: node)
    }

    /// An operand's text with the member it reads off `base` replaced — `parsedConfig.# == nil`.
    private static func shape(of operand: [Syntax], base: String) -> String {
        let reads = Set(operand.flatMap { memberReads(in: $0) }
            .filter { baseName(of: $0) == base }
            .map(\.declName.baseName.id))
        return operand.flatMap { $0.tokens(viewMode: .sourceAccurate) }
            .map { reads.contains($0.id) ? "#" : $0.text }
            .joined(separator: " ")
    }

    // MARK: - Statement runs

    /// The runs in a statement list: maximal runs of consecutive statements with one template.
    static func runs(inStatements list: CodeBlockItemListSyntax) -> [Run] {
        let items = Array(list)
        let templates = items.map(template(of:))
        var found: [Run] = []
        var start = 0
        while start < items.count {
            var end = start
            while end + 1 < items.count, let current = templates[start], templates[end + 1] == current {
                end += 1
            }
            if templates[start] != nil, end - start + 1 >= minMembers {
                found += runs(inItems: items, run: start...end)
            }
            start = end + 1
        }
        return found
    }

    /// The members each value has read across `run`, with the single-member statements on either
    /// side absorbed.
    private static func runs(inItems items: [CodeBlockItemSyntax], run: ClosedRange<Int>) -> [Run] {
        var membersByBase: [String: [String]] = [:]
        for index in run {
            for (base, members) in reads(in: [Syntax(items[index])]) {
                membersByBase[base, default: []].append(contentsOf: members)
            }
        }
        let cores = membersByBase.mapValues(Set.init)
        for neighbour in [run.lowerBound - 1, run.upperBound + 1] where items.indices.contains(neighbour) {
            for (base, members) in reads(in: [Syntax(items[neighbour])])
            where members.count == 1 && membersByBase[base] != nil {
                membersByBase[base, default: []].append(contentsOf: members)
            }
        }
        return sortedRuns(membersByBase, cores: cores, node: Syntax(items[run.lowerBound]))
    }

    /// A statement's text with every member it reads replaced by `#` and every name it binds by
    /// `$`, or `nil` when it reads no member — a run of statements that read nothing is not a run
    /// over anything.
    static func template(of item: CodeBlockItemSyntax) -> String? {
        let memberTokens = Set(memberReads(in: Syntax(item)).map(\.declName.baseName.id))
        guard !memberTokens.isEmpty else { return nil }
        let bound = boundNames(in: Syntax(item))
        return item.tokens(viewMode: .sourceAccurate).map { token in
            if memberTokens.contains(token.id) { return "#" }
            if case .identifier(let name) = token.tokenKind, bound.contains(name) { return "$" }
            return token.text
        }.joined(separator: " ")
    }

    /// Names a statement binds — `if let disabled = …`, `let ids = …`, a closure's parameters.
    private static func boundNames(in node: Syntax) -> Set<String> {
        var names: Set<String> = []
        for child in node.children(viewMode: .sourceAccurate) {
            if let identifier = child.as(IdentifierPatternSyntax.self) {
                names.insert(identifier.identifier.text)
            }
            names.formUnion(boundNames(in: child))
        }
        return names
    }

    // MARK: - Arrays of member reads

    /// `[config.disabledRules, config.optInRules, config.onlyRules]` — every element a member read
    /// off one value.
    static func run(inArrayLiteral node: ArrayExprSyntax) -> Run? {
        var base: String?
        var members: [String] = []
        for element in node.elements {
            guard let read = element.expression.as(MemberAccessExprSyntax.self),
                  let name = baseName(of: read), base == nil || base == name else { return nil }
            base = name
            members.append(read.declName.baseName.text)
        }
        guard let base, Set(members).count >= minMembers else { return nil }
        return Run(base: base, members: members, core: Set(members), node: Syntax(node))
    }

    // MARK: - Member reads

    /// Every member read in `nodes`, grouped by the value read: distinct members, in order.
    private static func reads(in nodes: [Syntax]) -> [String: [String]] {
        var grouped: [String: [String]] = [:]
        for node in nodes {
            for read in memberReads(in: node) {
                guard let base = baseName(of: read) else { continue }
                let member = read.declName.baseName.text
                if grouped[base]?.contains(member) != true {
                    grouped[base, default: []].append(member)
                }
            }
        }
        return grouped
    }

    /// Member reads off a lowercase identifier that are not method calls or assignment targets.
    static func memberReads(in node: Syntax) -> [MemberAccessExprSyntax] {
        var found: [MemberAccessExprSyntax] = []
        if let access = node.as(MemberAccessExprSyntax.self), baseName(of: access) != nil,
           !isCalled(access), !isAssigned(access) {
            found.append(access)
        }
        for child in node.children(viewMode: .sourceAccurate) {
            found += memberReads(in: child)
        }
        return found
    }

    /// The identifier a member is read off, when it names a value: not `self`, not a type.
    private static func baseName(of access: MemberAccessExprSyntax) -> String? {
        guard let reference = access.base?.as(DeclReferenceExprSyntax.self) else { return nil }
        let name = reference.baseName.text
        guard name != "self", let first = name.first, first.isLowercase || first == "$" else {
            return nil
        }
        return name
    }

    /// `x.a = …` — the left operand of an assignment, which `SwiftParser` leaves as the element
    /// before an `AssignmentExprSyntax` in an unfolded sequence.
    private static func isAssigned(_ access: MemberAccessExprSyntax) -> Bool {
        guard let elements = access.parent?.as(ExprListSyntax.self) else { return false }
        var iterator = elements.makeIterator()
        while let element = iterator.next() {
            if element.id == access.id {
                return iterator.next()?.is(AssignmentExprSyntax.self) == true
            }
        }
        return false
    }

    private static func isCalled(_ access: MemberAccessExprSyntax) -> Bool {
        guard let call = access.parent?.as(FunctionCallExprSyntax.self) else { return false }
        return call.calledExpression.id == access.id
    }

    private static func sortedRuns(
        _ membersByBase: [String: [String]],
        cores: [String: Set<String>],
        node: Syntax
    ) -> [Run] {
        membersByBase
            .filter { Set($0.value).count >= minMembers }
            .sorted { $0.key < $1.key }
            .map { Run(base: $0.key, members: $0.value, core: cores[$0.key] ?? [], node: node) }
    }

    // MARK: - Where

    /// The declaration a run sits in, for the message — `fetchAndPreview`, `init`, a computed
    /// property's name — or `nil` at file scope.
    static func enclosingDeclarationName(of node: Syntax) -> String? {
        var current = node.parent
        while let syntax = current {
            if let function = syntax.as(FunctionDeclSyntax.self) { return function.name.text }
            if syntax.is(InitializerDeclSyntax.self) { return "init" }
            if let binding = syntax.as(PatternBindingSyntax.self),
               let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                return name
            }
            current = syntax.parent
        }
        return nil
    }
}
