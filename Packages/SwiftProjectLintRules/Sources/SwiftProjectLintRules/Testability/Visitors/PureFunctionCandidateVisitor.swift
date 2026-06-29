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

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isCandidate(node) else { return .visitChildren }

        addIssue(
            severity: .info,
            message: "`\(node.name.text)(…)` looks pure and total — a good property-based-test "
                + "candidate (a function of its inputs)",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Run `swift-infer discover` on it, or add a PropertyLawKit test that "
                + "checks a law over generated inputs.",
            ruleName: .pureFunctionCandidate,
            symbol: node.name.text
        )
        return .visitChildren
    }

    /// A function is a candidate when it is free/`static`, takes inputs,
    /// returns an `Equatable` value, and is inferred `Effect.pure` (referentially
    /// transparent — synchronous, non-throwing, no trapping body, no impurity).
    /// Purity is delegated to the shared `PurityInferrer`; this method adds only
    /// the *testability* requirements (assertable return, has inputs, free/static).
    private func isCandidate(_ node: FunctionDeclSyntax) -> Bool {
        guard !fileIsTestOrFixture else { return false }
        // Free or `static` only — instance methods can read mutable `self`.
        guard isStatic(node) || isFileScope(node) else { return false }
        // The purity verdict — `.pure` on SwiftEffectInference's lattice — is the
        // unified signal; `_ = body` because the inferrer reads the node's body.
        guard purityInferrer.isPure(node) else { return false }
        return signatureIsAssertable(node.signature)
    }

    /// The candidacy half of the signature check (purity covers async/throws):
    /// takes inputs and returns a non-`Void`, `Equatable` value a property test
    /// can assert on.
    private func signatureIsAssertable(_ signature: FunctionSignatureSyntax) -> Bool {
        !signature.parameterClause.parameters.isEmpty
            && hasNonVoidReturn(signature)
            && returnTypeIsEquatable(signature)
    }

    private func isStatic(_ node: FunctionDeclSyntax) -> Bool {
        node.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
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
