import SwiftSyntax
import Testing

/// Which declarations create a purity oracle, found from the source and compared with a list.
///
/// `purityReadersDeclareWhatTheyRead` counts a rule file as an oracle reader when it names one of
/// ``oracleEntryPoints``. That is sound only while the list holds every declaration a rule can call
/// that creates an oracle, directly or through other declarations in the Visitors package. A list
/// kept by file went stale without a test failing: a new public function in a file already listed
/// created an oracle, a rule called it, and neither scan saw it. So this finds the entry points from
/// the source, declaration by declaration, and the list must equal what it finds.
extension PurityOracleEntryTests {

    /// A declaration a rule can call that creates an oracle, and what a call to it names.
    struct OracleEntryPoint: Hashable, Sendable, CustomStringConvertible {
        /// `Type.member`, one entry for all its overloads, or `Type.init(label:)`.
        let declaration: String
        /// The identifier tokens a call names, in order: `PropertyTestCandidacy.candidate(of:…)`
        /// names `PropertyTestCandidacy`, `candidate`, and `PackagePurityJoin(sources:)` names
        /// `PackagePurityJoin`, `sources`. Empty for an instance member, which a call reaches through
        /// a value no token names.
        let tokens: [String]

        var description: String { "\(declaration) \(tokens)" }
    }

    /// The public declarations that create an oracle. A rule file that names one must declare
    /// `.oracle` on its visitor (`purityReadersDeclareWhatTheyRead`), and `oracleEntryPointsAreKnown`
    /// fails when this list and the source disagree.
    static let oracleEntryPoints: Set<OracleEntryPoint> = [
        OracleEntryPoint(declaration: "PurityInferrer.init(fileID:line:)", tokens: ["PurityInferrer"]),
        // Never called from Sources (`noExplicitContextInSources`), but an entry point all the same.
        OracleEntryPoint(declaration: "PurityInferrer.init(context:)", tokens: ["PurityInferrer", "context"]),
        OracleEntryPoint(
            declaration: "PropertyTestCandidacy.candidate", tokens: ["PropertyTestCandidacy", "candidate"]
        ),
        OracleEntryPoint(declaration: "PropertyTestCandidacy.shape", tokens: ["PropertyTestCandidacy", "shape"]),
        OracleEntryPoint(
            declaration: "CleanInstanceMethodCatalog.build", tokens: ["CleanInstanceMethodCatalog", "build"]
        ),
        OracleEntryPoint(declaration: "PackagePurityJoin.init(sources:)", tokens: ["PackagePurityJoin", "sources"])
    ]

    @Test("every public declaration in the Visitors package that creates an oracle is a listed entry point")
    func oracleEntryPointsAreKnown() {
        let found = Self.publicOracleEntryPoints(in: Self.sources.filter { $0.path.hasPrefix(Self.visitorsSources) })
        let instance = found.filter(\.tokens.isEmpty).map(\.declaration).sorted()
        let advice = "a rule reaches an instance member through a value no scan can name: create the oracle "
            + "in a static member or an initializer"
        #expect(instance.isEmpty, "\(instance) create an oracle — \(advice)")
        let unlisted = found.subtracting(Self.oracleEntryPoints).map(\.description).sorted()
        let stale = Self.oracleEntryPoints.subtracting(found).map(\.description).sorted()
        #expect(found == Self.oracleEntryPoints, "list \(unlisted) in oracleEntryPoints; no longer found: \(stale)")
    }

    /// The declarations in `files` that create an oracle when they run and that code outside the
    /// package can call: public, in types that are public all the way out.
    ///
    /// A declaration creates an oracle when its tokens hold `PurityInferrer(` or name `PurityInferrer`
    /// beside a `.init` (`PurityInferrer.init()`, `let o: PurityInferrer = .init()`); when they hold a
    /// call to another declaration that does — by its type's name from anywhere
    /// (`PropertyTestCandidacy.candidate`), or by its own name from inside the same type; or, for an
    /// initializer, when a stored property of its type is initialized with one. That is run to a
    /// fixpoint, so a public function reaching an oracle through private and internal helpers, in any
    /// file of the package, is found.
    static func publicOracleEntryPoints(in files: [SourceFile]) -> Set<OracleEntryPoint> {
        let scan = OracleReachScan(files)
        return Set(scan.reaching.filter(scan.isCallableOutsideThePackage).map(\.entryPoint))
    }

    /// The entry points a rule file can name: the listed ones, and every static member, labelled
    /// initializer or file-scope function declared in a rule package that reaches an oracle — a
    /// helper in one visitor's file creates an oracle for every visitor that calls it, in whatever
    /// file.
    ///
    /// An initializer a call makes without a label — `init()`, `init(_:)`, the implicit one — would
    /// be keyed by the type's bare name, which a registrar names too (`visitor: X.self`). The registry
    /// creates visitors from their metatype, never by a call, so counting the name would make every
    /// registrar of a visitor that stores an oracle a reader. Those are left out. The gap that leaves
    /// is a helper class built with one in another visitor's file, which only the corpus-driven
    /// `everyRuleAloneReadsOnlyWhatItDeclares` sees.
    static func readerEntryPoints(in files: [SourceFile]) -> Set<OracleEntryPoint> {
        let scan = OracleReachScan(files.filter { file in
            file.path.hasPrefix(visitorsSources) || rulePackages.contains(where: file.path.hasPrefix)
        })
        let rules = scan.reaching.filter { member in
            let unlabelledInitializer = member.kind == .initializer && member.callLabel == nil
            return rulePackages.contains(where: member.file.hasPrefix) && !unlabelledInitializer
        }
        return oracleEntryPoints.union(rules.map(\.entryPoint).filter { !$0.tokens.isEmpty })
    }
}

/// A declaration with a body, as the reach scan sees it.
private struct ScannedMember {

    enum Kind {
        case function, initializer, property, storedInstanceProperty, subscriptMember
    }

    let file: String
    let kind: Kind
    /// As it is declared: `candidate`, `init(sources:)`, `subscript(_:)`.
    let name: String
    /// The enclosing types, outermost first; empty at file scope.
    let enclosingTypes: [String]
    /// A static member, a file-scope one, or an initializer: called without a value.
    let isStatic: Bool
    /// `public` or `open`, by its own modifier or its extension's.
    let isPublic: Bool
    /// An initializer's first argument label, when a call must spell it.
    let callLabel: String?
    /// Every token of the declaration but its own name.
    let tokens: [String]
    let tokenSet: Set<String>

    var type: String { enclosingTypes.last ?? "" }
    var scope: String { enclosingTypes.first ?? "" }

    /// What a call to it from another type spells, in tokens.
    var externalPattern: [String]? {
        switch kind {
        case .initializer:
            return [type, "("] + (callLabel.map { [$0, ":"] } ?? [])

        case .storedInstanceProperty:
            return nil

        case .function, .property, .subscriptMember:
            if enclosingTypes.isEmpty { return kind == .function ? [name, "("] : [name] }
            guard isStatic else { return nil }
            return kind == .subscriptMember ? [type, "["] : [type, ".", name]
        }
    }

    /// What a call to it from inside its own type spells.
    var scopePatterns: [[String]] {
        switch kind {
        case .initializer:
            let label = callLabel.map { [$0, ":"] } ?? []
            return [["Self", "("] + label, ["init", "("] + label]

        case .function, .property:
            return [[name]]

        case .storedInstanceProperty, .subscriptMember:
            return []
        }
    }

    var entryPoint: PurityOracleEntryTests.OracleEntryPoint {
        // A function's overloads share `Type.name`, so they are one entry point.
        let declaration = type.isEmpty ? name : "\(type).\(name)"
        let tokens: [String] = switch kind {
        case .initializer:
            [type] + (callLabel.map { [$0] } ?? [])

        case .function, .property, .subscriptMember, .storedInstanceProperty:
            enclosingTypes.isEmpty ? [name] : isStatic ? [type, name] : []
        }
        return .init(declaration: declaration, tokens: tokens)
    }

    /// Creates an oracle itself: `PurityInferrer(…)`, or `PurityInferrer` named beside a `.init`,
    /// which is how `PurityInferrer.init()` and `let o: PurityInferrer = .init()` spell it.
    var createsAnOracle: Bool {
        guard tokenSet.contains("PurityInferrer") else { return false }
        return spells(["PurityInferrer", "("]) || spells([".", "init"])
    }

    func spells(_ pattern: [String]) -> Bool {
        guard let first = pattern.first, tokenSet.contains(first) else { return false }
        let width = pattern.count
        return tokens.indices.dropLast(width - 1).contains { Array(tokens[$0..<($0 + width)]) == pattern }
    }
}

/// Which declarations in a set of files reach an oracle; see `publicOracleEntryPoints(in:)`.
private struct OracleReachScan {

    private let members: [ScannedMember]
    private let declaredTypes: Set<String>
    private let publicTypes: Set<String>
    let reaching: [ScannedMember]

    init(_ files: [PurityOracleEntryTests.SourceFile]) {
        var members: [ScannedMember] = []
        var declaredTypes: Set<String> = []
        var publicTypes: Set<String> = []
        for file in files {
            let collector = MemberCollector(file: file.path)
            collector.walk(file.tree)
            members += collector.members
            declaredTypes.formUnion(collector.declaredTypes)
            publicTypes.formUnion(collector.publicTypes)
        }
        members += Self.implicitInitializers(of: members)
        self.members = members
        self.declaredTypes = declaredTypes
        self.publicTypes = publicTypes
        reaching = Self.fixpoint(members).sorted().map { members[$0] }
    }

    func isCallableOutsideThePackage(_ member: ScannedMember) -> Bool {
        // A type the package does not declare — `extension FunctionDeclSyntax` — is someone else's
        // public type, or the extension could not be public.
        member.isPublic && member.kind != .storedInstanceProperty
            && member.enclosingTypes.allSatisfy { publicTypes.contains($0) || !declaredTypes.contains($0) }
    }

    /// The members that reach an oracle, by index.
    private static func fixpoint(_ members: [ScannedMember]) -> Set<Int> {
        var reaching: Set<Int> = []
        var changed = true
        while changed {
            changed = false
            var external: [[String]] = []
            var scoped: [String: [[String]]] = [:]
            var storing: Set<String> = []
            for index in reaching {
                let member = members[index]
                external += member.externalPattern.map { [$0] } ?? []
                if !member.scope.isEmpty { scoped[member.scope, default: []] += member.scopePatterns }
                if member.kind == .storedInstanceProperty { storing.insert(member.type) }
            }
            for index in members.indices where !reaching.contains(index) {
                let member = members[index]
                let byStorage = member.kind == .initializer && storing.contains(member.type)
                let reaches = member.createsAnOracle || byStorage
                if reaches || (external + (scoped[member.scope] ?? [])).contains(where: member.spells) {
                    reaching.insert(index)
                    changed = true
                }
            }
        }
        return reaching
    }

    /// The `init()` a type with stored defaults and no initializer of its own gets. Never public —
    /// Swift's implicit initializers are internal — but a call to one inside the package counts.
    private static func implicitInitializers(of members: [ScannedMember]) -> [ScannedMember] {
        let initialized = Set(members.filter { $0.kind == .initializer }.map(\.enclosingTypes))
        var storing: [[String]: String] = [:]
        for member in members where member.kind == .storedInstanceProperty {
            guard !initialized.contains(member.enclosingTypes) else { continue }
            storing[member.enclosingTypes] = storing[member.enclosingTypes] ?? member.file
        }
        return storing.map { types, file in
            ScannedMember(
                file: file, kind: .initializer, name: "init()", enclosingTypes: types, isStatic: true,
                isPublic: false, callLabel: nil, tokens: [], tokenSet: []
            )
        }
    }
}

/// Every function, initializer, subscript and property in a file, with the types around it.
private final class MemberCollector: SyntaxVisitor {

    private struct Frame {
        let type: String
        let isPublicExtension: Bool
    }

    private(set) var members: [ScannedMember] = []
    private(set) var declaredTypes: Set<String> = []
    private(set) var publicTypes: Set<String> = []
    private var frames: [Frame] = []
    private let file: String

    init(file: String) {
        self.file = file
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { declare(node.name.text, node.modifiers) }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { declare(node.name.text, node.modifiers) }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { declare(node.name.text, node.modifiers) }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { declare(node.name.text, node.modifiers) }
    /// A requirement has no body to create an oracle in; a protocol extension is an extension.
    override func visit(_: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let type = PurityOracleEntryTests.typeName(of: node.extendedType)
        frames.append(Frame(type: type, isPublicExtension: Self.isPublicOrOpen(Self.access(node.modifiers))))
        return .visitChildren
    }

    override func visitPost(_: StructDeclSyntax) { frames.removeLast() }
    override func visitPost(_: ClassDeclSyntax) { frames.removeLast() }
    override func visitPost(_: EnumDeclSyntax) { frames.removeLast() }
    override func visitPost(_: ActorDeclSyntax) { frames.removeLast() }
    override func visitPost(_: ExtensionDeclSyntax) { frames.removeLast() }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        record(.function, node.name.text, node.modifiers, Syntax(node), leaving: node.name)
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let parameters = node.signature.parameterClause.parameters
        // `init(fileID: = #fileID, …)` is called as `T()`, and `init(_:)` as `T(x)`.
        let label = parameters.first.flatMap { first in
            first.defaultValue == nil && first.firstName.text != "_" ? first.firstName.text : nil
        }
        record(.initializer, "init(\(Self.labels(parameters)))", node.modifiers, Syntax(node), callLabel: label)
        return .skipChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = "subscript(\(Self.labels(node.parameterClause.parameters)))"
        record(.subscriptMember, name, node.modifiers, Syntax(node))
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            let stored = binding.accessorBlock.map(Self.onlyObserves) ?? true
            let instance = !frames.isEmpty && !Self.isStatic(node.modifiers)
            let kind: ScannedMember.Kind = stored && instance ? .storedInstanceProperty : .property
            record(kind, binding.pattern.trimmedDescription, node.modifiers, Syntax(binding), leaving: nil)
        }
        return .skipChildren
    }

    private func declare(_ name: String, _ modifiers: DeclModifierListSyntax) -> SyntaxVisitorContinueKind {
        declaredTypes.insert(name)
        if isPublic(modifiers) { publicTypes.insert(name) }
        frames.append(Frame(type: name, isPublicExtension: false))
        return .visitChildren
    }

    private func record(
        _ kind: ScannedMember.Kind,
        _ name: String,
        _ modifiers: DeclModifierListSyntax,
        _ syntax: Syntax,
        leaving ownName: TokenSyntax? = nil,
        callLabel: String? = nil
    ) {
        let tokens = syntax.tokens(viewMode: .sourceAccurate).filter { $0.id != ownName?.id }.map(\.text)
        members.append(ScannedMember(
            file: file,
            kind: kind,
            name: name,
            enclosingTypes: frames.map(\.type),
            isStatic: frames.isEmpty || kind == .initializer || Self.isStatic(modifiers),
            isPublic: isPublic(modifiers),
            callLabel: callLabel,
            tokens: tokens,
            tokenSet: Set(tokens)
        ))
    }

    /// Public by its own modifier, or by its extension's when it has none.
    private func isPublic(_ modifiers: DeclModifierListSyntax) -> Bool {
        guard let access = Self.access(modifiers) else { return frames.last?.isPublicExtension ?? false }
        return Self.isPublicOrOpen(access)
    }

    private static func isPublicOrOpen(_ access: Keyword?) -> Bool {
        access == .public || access == .open
    }

    /// The access modifier `modifiers` spell, if any.
    private static func access(_ modifiers: DeclModifierListSyntax) -> Keyword? {
        let levels: Set<Keyword> = [.public, .open, .package, .internal, .fileprivate, .private]
        for modifier in modifiers {
            if case .keyword(let keyword) = modifier.name.tokenKind, levels.contains(keyword) { return keyword }
        }
        return nil
    }

    private static func isStatic(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) }
    }

    private static func onlyObserves(_ block: AccessorBlockSyntax) -> Bool {
        guard case .accessors(let list) = block.accessors else { return false }   // `{ … }`: a getter
        return list.allSatisfy {
            $0.accessorSpecifier.tokenKind == .keyword(.willSet) || $0.accessorSpecifier.tokenKind == .keyword(.didSet)
        }
    }

    private static func labels(_ parameters: FunctionParameterListSyntax) -> String {
        parameters.map { $0.firstName.text + ":" }.joined()
    }
}
