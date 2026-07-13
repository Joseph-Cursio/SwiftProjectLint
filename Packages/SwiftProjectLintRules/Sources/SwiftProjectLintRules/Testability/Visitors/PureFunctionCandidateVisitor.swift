import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// The positive testability signal: surfaces free / `static` functions that
/// look pure and total — they take parameters, return a value, aren't `async`,
/// and their body shows no obvious impurity (no I/O, logging, randomness, or
/// global access). These are the low-hanging fruit for property-based testing,
/// and the seed the lint → infer → verify pipeline (Idea #2) hands to
/// `swift-infer`.
///
/// Conservative by design — it under-suggests rather than flag an impure
/// function. `info` severity; opt-in.
final class PureFunctionCandidateVisitor: BasePatternVisitor {

    private var fileIsTestOrFixture = false

    /// Shared purity inference on `SwiftEffectInference.Effect`. A function is
    /// a candidate only when this infers `.pure` — the testability rule and the
    /// idempotency rules now decide purity through the same vocabulary.
    private let purityInferrer = PurityInferrer()

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        fileIsTestOrFixture = isTestOrFixtureFile()
    }

    /// What a candidate is a function *of* — which decides how a property test drives it.
    private enum Candidacy {
        /// A function of its arguments alone. Generate inputs and call it.
        case ofInputs

        /// A function of `(self, arguments)`: it reads immutable stored state, so a test has to
        /// build a `self` first. Still perfectly property-testable — just not free-standing.
        case ofSelfAndInputs
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let candidacy = candidacy(of: node) else { return .visitChildren }

        let shape: String
        let advice: String
        switch candidacy {
        case .ofInputs:
            shape = "a function of its inputs"
            advice = "Run `swift-infer discover` on it, or add a PropertyLawKit test that "
                + "checks a law over generated inputs."

        case .ofSelfAndInputs:
            shape = "a function of `self` and its inputs — it reads only immutable stored state"
            advice = "Construct the enclosing value in the test and generate its inputs, or lift "
                + "the body into a free function if it turns out not to need `self` at all."
        }

        addIssue(
            severity: .info,
            message: "`\(node.name.text)(…)` looks pure and total — a good property-based-test "
                + "candidate (\(shape))",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: advice,
            ruleName: .pureFunctionCandidate,
            symbol: node.name.text
        )
        return .visitChildren
    }

    /// What `node` is a function of, or `nil` when it is not a candidate at all.
    ///
    /// Purity is delegated to the shared `PurityInferrer` (referentially transparent —
    /// synchronous, non-throwing, no trapping body, no impurity markers). This method adds the
    /// *testability* requirements: an assertable return, and something to vary.
    ///
    /// **Instance methods are candidates now.** They used to be refused outright, on the grounds
    /// that they "can read mutable `self`" — true of some, and the reason to *ask* rather than to
    /// refuse. In an app almost all logic is instance methods, so refusing them left the seed
    /// manifest nearly empty on exactly the codebases the lint → infer loop is aimed at.
    /// `SelfAccessAnalyzer` answers the question the old guard was asking.
    private func candidacy(of node: FunctionDeclSyntax) -> Candidacy? {
        guard !fileIsTestOrFixture else { return nil }
        // The purity verdict — `.pure` on SwiftEffectInference's lattice — is the unified signal.
        guard purityInferrer.isPure(node) else { return nil }
        guard returnIsAssertable(node.signature) else { return nil }

        if isStatic(node) || isFileScope(node) {
            // Unchanged: a free or static function with no inputs is a constant, not a property.
            guard hasInputs(node.signature) else { return nil }
            return .ofInputs
        }

        return instanceMethodCandidacy(of: node)
    }

    /// The candidacy of an instance method, decided by what it reads from `self`.
    private func instanceMethodCandidacy(of node: FunctionDeclSyntax) -> Candidacy? {
        // A `mutating` method's whole purpose is to change `self`; it is not a function of it.
        guard !isMutating(node) else { return nil }
        // Actor isolation puts the method behind `await`, and the purity oracle has already ruled
        // out `async` — but a nested `nonisolated` method could slip through, so refuse the shape.
        guard let container = enclosingTypeContainer(of: node), !container.isActor else { return nil }

        switch SelfAccessAnalyzer.access(of: node, storedProperties: container.storedProperties) {
        case .unresolvedOrMutable:
            return nil

        case .none:
            // Reads nothing from `self` — a free function that happens to live in a type. It still
            // needs inputs, for the same reason a free one does.
            guard hasInputs(node.signature) else { return nil }
            return .ofInputs

        case .immutableStoredOnly:
            // `self` *is* the input. A nullary method reading immutable stored state is a
            // perfectly good property subject — vary the value, not the arguments.
            return .ofSelfAndInputs
        }
    }

    /// Returns a non-`Void`, `Equatable` value a property test can assert on.
    private func returnIsAssertable(_ signature: FunctionSignatureSyntax) -> Bool {
        hasNonVoidReturn(signature) && returnTypeIsEquatable(signature)
    }

    private func hasInputs(_ signature: FunctionSignatureSyntax) -> Bool {
        !signature.parameterClause.parameters.isEmpty
    }

    private func isStatic(_ node: FunctionDeclSyntax) -> Bool {
        node.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
    }

    private func isMutating(_ node: FunctionDeclSyntax) -> Bool {
        node.modifiers.contains { $0.name.tokenKind == .keyword(.mutating) }
    }

    /// The type a method is declared in, with the stored properties visible in this file.
    private struct TypeContainer {
        let name: String
        let isActor: Bool
        let storedProperties: [String: StoredProperty]
    }

    /// Walks out to the type (or extension) `node` is declared in, then gathers the stored
    /// properties of *every* declaration of that type in this file.
    ///
    /// The second half matters: `getFileIcon(for:)` lives in `MacCloudViewModel+Helpers.swift`, an
    /// extension, and an extension's own member block holds no stored properties at all. Gathering
    /// across the file means a method declared in an extension still sees the stored properties of
    /// a primary declaration that sits alongside it. What it *cannot* see is a primary declaration
    /// in another file — and a reference the analyzer cannot resolve disqualifies the candidate,
    /// which is the safe direction.
    private func enclosingTypeContainer(of node: FunctionDeclSyntax) -> TypeContainer? {
        var cursor: Syntax? = Syntax(node).parent
        while let current = cursor {
            if let structDecl = current.as(StructDeclSyntax.self) {
                return container(named: structDecl.name.text, isActor: false, from: node)
            }
            if let classDecl = current.as(ClassDeclSyntax.self) {
                return container(named: classDecl.name.text, isActor: false, from: node)
            }
            if let enumDecl = current.as(EnumDeclSyntax.self) {
                return container(named: enumDecl.name.text, isActor: false, from: node)
            }
            if let actorDecl = current.as(ActorDeclSyntax.self) {
                return container(named: actorDecl.name.text, isActor: true, from: node)
            }
            if let extensionDecl = current.as(ExtensionDeclSyntax.self) {
                let name = extensionDecl.extendedType.trimmedDescription
                return container(named: name, isActor: false, from: node)
            }
            cursor = current.parent
        }
        return nil
    }

    /// Every stored property declared for `name` anywhere in this file — in its primary
    /// declaration and in any extension of it.
    private func container(named name: String, isActor: Bool, from node: some SyntaxProtocol) -> TypeContainer {
        guard let file = node.root.as(SourceFileSyntax.self) else {
            return TypeContainer(name: name, isActor: isActor, storedProperties: [:])
        }

        let collector = StoredPropertyCollector(typeName: name, viewMode: .sourceAccurate)
        collector.walk(file)
        return TypeContainer(
            name: name,
            isActor: isActor || collector.sawActorDeclaration,
            storedProperties: collector.properties
        )
    }

    private func isFileScope(_ node: FunctionDeclSyntax) -> Bool {
        guard let item = node.parent?.as(CodeBlockItemSyntax.self),
              let list = item.parent?.as(CodeBlockItemListSyntax.self) else {
            return false
        }
        return list.parent?.is(SourceFileSyntax.self) == true
    }

    private func hasNonVoidReturn(_ signature: FunctionSignatureSyntax) -> Bool {
        guard let returnType = signature.returnClause?.type.trimmedDescription else {
            return false
        }
        return returnType != "Void" && returnType != "()"
    }

    /// Standard-library types whose values are `Equatable` out of the box. The
    /// container names (`Array`, `Set`, …) are `Equatable` when their elements
    /// are; `baseTypeName` unwraps `[T]` to `T` so a custom element is still
    /// checked against the project's conformance index.
    private static let equatableStdlibTypes: Set<String> = [
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Double", "Float", "Float16", "CGFloat", "Decimal",
        "Bool", "String", "Character", "Substring", "StaticString",
        "Date", "UUID", "URL", "Data", "TimeInterval",
        "Array", "Set", "Dictionary", "Range", "ClosedRange"
    ]

    /// True when the return type can be compared for equality — a stdlib
    /// `Equatable` type, or a project type the pre-scan found declaring
    /// `Equatable`/`Hashable`/`Comparable`. Tuples and closures (no nominal
    /// base) are treated as non-assertable and drop the candidate.
    private func returnTypeIsEquatable(_ signature: FunctionSignatureSyntax) -> Bool {
        guard let returnType = signature.returnClause?.type,
              let base = baseTypeName(returnType) else {
            return false
        }
        return Self.equatableStdlibTypes.contains(base) || knownEquatableTypes.contains(base)
    }

    // Purity inference (impurity markers, totality) lives in the shared
    // `PurityInferrer` (SwiftProjectLintVisitors) so the testability rule and
    // the idempotency rules decide purity through the same `Effect.pure` verdict.

    /// The underlying nominal name of a type, unwrapping optionals and arrays:
    /// `Foo?` → `Foo`, `[Foo]` → `Foo`, `Foo<Bar>` → `Foo`. `[K: V]` resolves to
    /// `Dictionary`. Returns `nil` for tuples, closures, and other non-nominal
    /// types.
    private func baseTypeName(_ type: TypeSyntax) -> String? {
        if let optional = type.as(OptionalTypeSyntax.self) {
            return baseTypeName(optional.wrappedType)
        }
        if let implicit = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return baseTypeName(implicit.wrappedType)
        }
        if let array = type.as(ArrayTypeSyntax.self) {
            return baseTypeName(array.element)
        }
        if type.is(DictionaryTypeSyntax.self) {
            return "Dictionary"
        }
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        return nil
    }
}

/// Gathers the stored properties a named type declares anywhere in one file — in its primary
/// declaration and in every extension of it.
private final class StoredPropertyCollector: SyntaxVisitor {
    private let typeName: String

    var properties: [String: StoredProperty] = [:]
    var sawActorDeclaration = false

    init(typeName: String, viewMode: SyntaxTreeViewMode) {
        self.typeName = typeName
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        absorb(node.name.text, node.memberBlock.members)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        absorb(node.name.text, node.memberBlock.members)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        absorb(node.name.text, node.memberBlock.members)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == typeName { sawActorDeclaration = true }
        absorb(node.name.text, node.memberBlock.members)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        absorb(node.extendedType.trimmedDescription, node.memberBlock.members)
        return .visitChildren
    }

    private func absorb(_ name: String, _ members: MemberBlockItemListSyntax) {
        guard name == typeName else { return }
        properties.merge(StoredProperty.declared(in: members)) { _, new in new }
    }
}
