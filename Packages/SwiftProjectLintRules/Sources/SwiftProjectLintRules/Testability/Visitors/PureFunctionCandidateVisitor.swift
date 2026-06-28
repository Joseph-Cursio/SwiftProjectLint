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

    /// Strong impurity markers — any in the body disqualifies the function.
    private static let impureMarkers: Set<String> = [
        "print", "NSLog", "FileManager", "URLSession", "UserDefaults",
        "NotificationCenter", "DispatchQueue",
        "arc4random", "arc4random_uniform", "drand48",
        "random", "randomElement", "shuffled"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        fileIsTestOrFixture = isTestOrFixtureFile()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let body = node.body, isCandidate(node, body: body) else { return .visitChildren }

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

    /// A function is a candidate when it is free/`static`, takes inputs, is total
    /// (synchronous, non-throwing, no trapping body, no impurity), and returns an
    /// `Equatable` value. Split into grouped predicates to keep each one simple.
    private func isCandidate(_ node: FunctionDeclSyntax, body: CodeBlockSyntax) -> Bool {
        guard !fileIsTestOrFixture else { return false }
        // Free or `static` only — instance methods can read mutable `self`.
        guard isStatic(node) || isFileScope(node) else { return false }
        return signatureQualifies(node.signature) && bodyQualifies(body)
    }

    /// Takes inputs, returns an `Equatable` value, and is synchronous + total at
    /// the signature level (no `async`, no `throws`).
    private func signatureQualifies(_ signature: FunctionSignatureSyntax) -> Bool {
        !signature.parameterClause.parameters.isEmpty
            && hasNonVoidReturn(signature)
            && signature.effectSpecifiers?.asyncSpecifier == nil
            && signature.effectSpecifiers?.throwsClause == nil
            && returnTypeIsEquatable(signature)
    }

    /// The body shows no impurity and can't trap (is total).
    private func bodyQualifies(_ body: CodeBlockSyntax) -> Bool {
        !bodyLooksImpure(body) && bodyIsTotal(body)
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

    private func bodyLooksImpure(_ body: CodeBlockSyntax) -> Bool {
        body.tokens(viewMode: .sourceAccurate).contains { Self.impureMarkers.contains($0.text) }
    }

    /// True when nothing in the body can trap (crash) at runtime — the property
    /// that lets us treat the function as total. Force-unwrap (`!`), `try!`,
    /// `as!`, and the `fatalError` / `precondition` / `assert` family all
    /// introduce inputs for which there is no return value, so a property test
    /// over generated inputs would hit a crash rather than a falsified law.
    private func bodyIsTotal(_ body: CodeBlockSyntax) -> Bool {
        let checker = TotalityChecker(viewMode: .sourceAccurate)
        checker.walk(body)
        return checker.isTotal
    }
}

/// Walks a function body looking for any runtime trap that breaks totality.
private final class TotalityChecker: SyntaxVisitor {

    private(set) var isTotal = true

    /// Standard-library trap functions: reaching them means the function has no
    /// return value for some inputs.
    private static let trapFunctions: Set<String> = [
        "fatalError", "preconditionFailure", "precondition",
        "assert", "assertionFailure"
    ]

    override func visit(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
        _ = node
        isTotal = false
        return .skipChildren
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        if node.questionOrExclamationMark?.text == "!" { isTotal = false }
        return .visitChildren
    }

    override func visit(_ node: AsExprSyntax) -> SyntaxVisitorContinueKind {
        if node.questionOrExclamationMark?.text == "!" { isTotal = false }
        return .visitChildren
    }

    // Raw (unfolded) parse trees represent `x as! T` as an `UnresolvedAsExprSyntax`
    // inside a `SequenceExprSyntax`; the folded `AsExprSyntax` form only appears
    // after operator-precedence folding, which the linter doesn't run.
    override func visit(_ node: UnresolvedAsExprSyntax) -> SyntaxVisitorContinueKind {
        if node.questionOrExclamationMark?.text == "!" { isTotal = false }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let callee = node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
           Self.trapFunctions.contains(callee) {
            isTotal = false
        }
        return .visitChildren
    }
}
