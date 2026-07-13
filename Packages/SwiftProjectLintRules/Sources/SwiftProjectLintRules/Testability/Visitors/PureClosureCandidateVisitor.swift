import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// The property test hiding inside a closure.
///
/// `pureFunctionCandidate` can only point at a *declaration*. A great deal of the pure logic in
/// real Swift has none: a `filter` predicate or a `sorted(by:)` comparator written inline is a pure
/// function in everything but syntax, and being anonymous is the only thing standing between it and
/// a property test. The linter had nothing to say about them, so neither did the reader.
///
/// The motivating case, and the reason this rule exists at all:
///
///     let immediateChildren = allFiles.filter { file in
///         let relativePath = file.path.replacingOccurrences(of: currentPath, with: "")
///         return relativePath.split(separator: "/").count <= 1
///     }
///     files = immediateChildren.sorted { file1, file2 in
///         if file1.isFolder != file2.isFolder { return file1.isFolder }
///         return file1.name.localizedCaseInsensitiveCompare(file2.name) == .orderedAscending
///     }
///
/// Two pure functions with no names. The first contains a real bug — `replacingOccurrences` strips
/// *every* match, not just the leading one, so a grandchild is listed as a child — and it went
/// unnoticed because there was nothing to write a test against. Name it and the property writes
/// itself.
///
/// **A capture is not an impurity.** That predicate captures `currentPath`, which is a `var`.
/// Irrelevant: lift the body into `isImmediateChild(_ path: String, of parent: String)` and the
/// capture *becomes a parameter*. Refusing captured state would refuse the best finding this rule
/// has. What no extraction rescues is a closure that **writes** to what it captured — that one is
/// refuted, by the shared purity oracle.
///
/// `info` severity; opt-in. Reports a refactor, not a defect.
final class PureClosureCandidateVisitor: BasePatternVisitor {

    private var fileIsTestOrFixture = false
    private let purityInferrer = PurityInferrer()

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        fileIsTestOrFixture = isTestOrFixtureFile()
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard !fileIsTestOrFixture,
              let operation = CollectionOperation(call: node),
              let closure = node.trailingClosure ?? firstClosureArgument(of: node),
              closure.statements.count >= operation.minimumStatements,
              purityInferrer.isPure(closure) else {
            return .visitChildren
        }

        addIssue(
            severity: .info,
            message: "The closure passed to `\(operation.name)` is pure — a property-based-test "
                + "candidate with no name to test. \(operation.law)",
            filePath: getFilePath(for: Syntax(closure)),
            lineNumber: getLineNumber(for: Syntax(closure)),
            suggestion: "Lift it into a named function. Anything it captures becomes a parameter, "
                + "and what is left is a pure function you can generate inputs for.",
            ruleName: .pureClosureCandidate,
            symbol: operation.name
        )
        return .visitChildren
    }

    /// The first closure passed as an ordinary (non-trailing) argument — `sorted(by: { … })`.
    private func firstClosureArgument(of call: FunctionCallExprSyntax) -> ClosureExprSyntax? {
        call.arguments.lazy
            .compactMap { $0.expression.as(ClosureExprSyntax.self) }
            .first
    }
}

/// A higher-order collection operation whose closure argument is a pure function by contract.
///
/// Deliberately a fixed list rather than "any call taking a closure". `Task { … }`,
/// `withAnimation { … }` and `DispatchQueue.main.async { … }` also take closures, and a closure run
/// for its effects is not a property waiting to be named. These are the operations whose closures
/// are *supposed* to be functions.
private struct CollectionOperation {
    let name: String

    /// The law worth stating once the closure has a name — the reason to bother extracting it.
    let law: String

    /// A one-statement `map { $0.name }` is a projection, not a property; naming it buys nothing.
    /// A comparator earns its finding at any size, because the law is about the *ordering*, not the
    /// body's complexity.
    let minimumStatements: Int

    init?(call: FunctionCallExprSyntax) {
        guard let callee = call.calledExpression.as(MemberAccessExprSyntax.self) else { return nil }

        switch callee.declName.baseName.text {
        case "sorted", "sort", "min", "max", "partition":
            self.name = callee.declName.baseName.text
            self.law = "A comparator must be a strict weak ordering: irreflexive, antisymmetric and "
                + "transitive. Sorting with one that is not can crash, and no example test will "
                + "tell you which triple broke it."
            self.minimumStatements = 1

        case "filter", "first", "contains", "allSatisfy", "drop", "prefix", "removeAll":
            self.name = callee.declName.baseName.text
            self.law = "A predicate is a total function of its inputs — generate them and state "
                + "what it must accept and reject."
            self.minimumStatements = 2

        case "map", "compactMap", "flatMap":
            self.name = callee.declName.baseName.text
            self.law = "A transform is a function of its input — generate inputs and state what "
                + "the result must satisfy."
            self.minimumStatements = 2

        case "reduce":
            self.name = "reduce"
            self.law = "A reducer's combine step is usually associative, and often has an identity "
                + "— both are laws a property test can check and an example cannot."
            self.minimumStatements = 2

        default:
            return nil
        }
    }
}
