import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// The pure function trapped inside an impure method.
///
/// `pureFunctionCandidate` points at a whole declaration and `pureClosureCandidate` points at a
/// closure. Neither can see the third and most valuable shape: **arithmetic with no boundary drawn
/// around it**, inlined in a method that also does network or disk I/O.
///
///     private func uploadRemainingChunks(of data: Data, …) async throws -> … {
///         let totalChunks = (data.count + chunkSize - 1) / chunkSize
///         var index = current.queuedChunks
///         while index < totalChunks {
///             let chunk = Data(data.dropFirst(index * chunkSize).prefix(chunkSize))
///             _ = try await uploadChunkWithRetry(…)          // ← the impurity
///             index += 1
///             progressHandler?(Double(index) / Double(totalChunks))
///         }
///     }
///
/// How many chunks; where chunk *n* starts; how far along we are. That is a function of
/// `(data.count, chunkSize, index)` and nothing else — it touches no network, no disk, no clock. But
/// it is welded to a `private async throws` method that needs a live session and a server, so *no
/// test can reach it*, and it is where two of this app's three real bugs live: an unclamped
/// server-supplied resume index that completes a partial upload, and an empty payload whose progress
/// never reaches `1.0`.
///
/// The rule reports the **refactor**, not a smell: lift the arithmetic into a value type and it
/// becomes a function you can generate inputs for — the chunks should tile the payload exactly, and
/// progress should terminate at 1.0.
///
/// **Three gates keep it from firing on everything**, and each one was put there by a finding:
///
/// - **The enclosing function must be impure.** Otherwise the rule re-reports every pure function in
///   the codebase, which `pureFunctionCandidate` already owns. A hand-audit of 85 functions caught
///   this: without the gate, the rule fires on `isValidFolderName`, which is *already* a named pure
///   function with nothing to extract.
/// - **Closure bodies are skipped.** `pureClosureCandidate` owns those, and a kernel that lives
///   wholly inside a `filter` predicate is that rule's finding, reported once.
/// - **Arithmetic must feed a decision.** A derived value that is merely *stored* is not a kernel —
///   it has to govern something: a loop bound, an index, a slice range, a comparison, or a progress
///   fraction. This is the clause that separates chunking math from a local variable someone
///   extracted for readability, and it is why `navigateUp`'s pure path arithmetic is deliberately
///   *not* reported here (its result is assigned, not used as a bound) — that shape is a
///   state-machine law, and it belongs to a different template.
///
/// `info` severity; opt-in. Reports a refactor, not a defect.
final class ExtractablePureKernelVisitor: BasePatternVisitor {

    private var fileIsTestOrFixture = false
    private let purityInferrer = PurityInferrer()

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        fileIsTestOrFixture = isTestOrFixtureFile()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !fileIsTestOrFixture,
              let body = node.body,
              // Gate 1: a *pure* function has no trapped kernel — it IS the kernel, and
              // `pureFunctionCandidate` reports it.
              !purityInferrer.isPure(node) else {
            return .visitChildren
        }

        let kernel = KernelScan(body: body)
        guard kernel.isWorthExtracting else { return .visitChildren }

        addIssue(
            severity: .info,
            message: "A pure kernel is trapped in this impure method — \(kernel.summary) depend "
                + "only on its parameters and locals, and nothing else in the method reaches them. "
                + "Lift them into a value type and they become property-testable: \(kernel.law)",
            filePath: getFilePath(for: Syntax(kernel.anchor)),
            lineNumber: getLineNumber(for: Syntax(kernel.anchor)),
            suggestion: "Extract the arithmetic into a value type constructed from those inputs "
                + "alone. The method keeps the I/O and asks the value type where the bytes are.",
            ruleName: .extractablePureKernel,
            symbol: node.name.text
        )
        return .visitChildren
    }
}

/// What the body contains, scored against the one question that matters: **is there arithmetic here
/// that governs a decision?**
///
/// Deliberately not a dataflow analysis. A kernel has no syntactic boundary — it is whatever set of
/// statements you *choose* to lift — so a precise "maximal pure set" is both hard and beside the
/// point: the reader draws the boundary, the rule only has to say *there is one here, and here is
/// what it is made of*. What the scan must get right is the **precision**, and precision comes from
/// demanding that arithmetic reach a governing position, not from tracing it exactly.
private struct KernelScan {

    /// A local `let`/`var` whose initialiser is arithmetic over locals, parameters and members —
    /// `let totalChunks = (data.count + chunkSize - 1) / chunkSize`.
    private var derivedBindings: [String] = []

    /// `Double(index) / Double(totalChunks)` — a fraction, which is the shape of every progress bug
    /// in this codebase.
    private var hasFraction = false

    /// A comparison one of whose sides is arithmetic, or references a derived binding —
    /// `index < totalChunks`, `progress - lastReported >= 0.01`.
    private var hasGoverningComparison = false

    /// `dropFirst(index * chunkSize)`, `prefix(n)`, `array[i + 1]` — arithmetic used as a slice or an
    /// index.
    private var hasSlicingArithmetic = false

    /// A fraction computed inline rather than bound to a name — so the message can mention it
    /// without saying "`progress` and the progress fraction".
    private var hasUnnamedFraction = false

    private(set) var anchor: Syntax

    init(body: CodeBlockSyntax) {
        self.anchor = Syntax(body)
        var collector = Collector()
        collector.walk(body)

        derivedBindings = collector.derivedBindings
        hasFraction = collector.hasFraction
        hasSlicingArithmetic = collector.hasSlicingArithmetic
        hasUnnamedFraction = collector.hasFraction && !collector.fractionIsNamed
        hasGoverningComparison = collector.governingComparisonReferencing(collector.derivedBindings)

        if let first = collector.firstArithmeticSite {
            anchor = first
        }
    }

    /// There must be **arithmetic**, and it must **govern something**.
    ///
    /// Both halves are load-bearing. Arithmetic alone fires on every byte-size string and every
    /// layout constant. A governing use alone fires on every `if` in the codebase. It is the
    /// conjunction — a value *computed* and then used as a bound, an index, a slice or a fraction —
    /// that picks out chunking math and progress tracking and essentially nothing else.
    var isWorthExtracting: Bool {
        let hasArithmetic = !derivedBindings.isEmpty || hasFraction
        let governs = hasGoverningComparison || hasSlicingArithmetic || hasFraction
        return hasArithmetic && governs && signalCount >= 2
    }

    private var signalCount: Int {
        var count = derivedBindings.count
        if hasFraction { count += 1 }
        if hasGoverningComparison { count += 1 }
        if hasSlicingArithmetic { count += 1 }
        return count
    }

    var summary: String {
        guard !derivedBindings.isEmpty else { return "the progress fraction here" }
        let named = derivedBindings.prefix(3).map { "`\($0)`" }.joined(separator: ", ")
        // Only mention the fraction separately when it is not already one of the names — otherwise
        // the message reads "`progress` and the progress fraction".
        return hasUnnamedFraction ? "\(named) and the progress fraction" : named
    }

    var law: String {
        if hasFraction, hasSlicingArithmetic {
            return "the parts should tile the whole exactly, and progress should terminate at 1.0 — "
                + "including for an empty input."
        }
        if hasFraction {
            return "progress should be monotonic, stay within 0...1, and terminate at 1.0 — "
                + "including for an empty input."
        }
        return "the parts should tile the whole exactly — no gap, no overlap — and the count should "
            + "be exactly `ceil(total / size)`."
    }
}

/// Walks a function body gathering the four signals, and **stops at a closure**: a kernel that lives
/// wholly inside one is `pureClosureCandidate`'s finding, and reporting it twice would teach the
/// reader that the two rules disagree when they do not.
private struct Collector {

    private(set) var derivedBindings: [String] = []
    private(set) var hasFraction = false
    private(set) var fractionIsNamed = false
    private(set) var hasSlicingArithmetic = false
    private(set) var firstArithmeticSite: Syntax?
    private var comparisons: [ExprSyntax] = []

    /// Calls that do not refute the kernel — a numeric conversion computes nothing you could not
    /// have written with an operator. Anything else in an initialiser means the binding is doing
    /// *work*, and work the analyser cannot see is work it must not vouch for.
    private static let pureConversions: Set<String> = [
        "Double", "Int", "Int64", "Int32", "UInt", "UInt64", "Float", "CGFloat"
    ]

    private static let slicingCalls: Set<String> = [
        "dropFirst", "dropLast", "prefix", "suffix", "removeFirst", "removeLast"
    ]

    private static let arithmeticOperators: Set<String> = ["+", "-", "*", "/", "%"]
    private static let comparisonOperators: Set<String> = ["<", ">", "<=", ">=", "==", "!="]

    mutating func walk(_ node: some SyntaxProtocol) {
        for child in node.children(viewMode: .sourceAccurate) {
            // A closure body belongs to `pureClosureCandidate`. Do not descend.
            if child.is(ClosureExprSyntax.self) { continue }

            if let binding = child.as(VariableDeclSyntax.self) {
                record(binding)
            }
            if let call = child.as(FunctionCallExprSyntax.self) {
                record(call)
            }
            if let sequence = child.as(SequenceExprSyntax.self) {
                record(sequence)
            }
            if let subscriptCall = child.as(SubscriptCallExprSyntax.self) {
                if containsArithmetic(Syntax(subscriptCall.arguments)) {
                    hasSlicingArithmetic = true
                }
            }
            walk(child)
        }
    }

    /// `let totalChunks = (data.count + chunkSize - 1) / chunkSize` — arithmetic, no opaque calls.
    private mutating func record(_ declaration: VariableDeclSyntax) {
        for binding in declaration.bindings {
            guard let value = binding.initializer?.value,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  containsArithmetic(Syntax(value)),
                  onlyPureCalls(Syntax(value)) else {
                continue
            }
            derivedBindings.append(name)
            if firstArithmeticSite == nil { firstArithmeticSite = Syntax(declaration) }
            if isFraction(Syntax(value)) {
                hasFraction = true
                fractionIsNamed = true
            }
        }
    }

    private mutating func record(_ call: FunctionCallExprSyntax) {
        guard let callee = call.calledExpression.as(MemberAccessExprSyntax.self) else { return }
        if Self.slicingCalls.contains(callee.declName.baseName.text),
           containsArithmetic(Syntax(call.arguments)) {
            hasSlicingArithmetic = true
            if firstArithmeticSite == nil { firstArithmeticSite = Syntax(call) }
        }
    }

    private mutating func record(_ sequence: SequenceExprSyntax) {
        let symbols = operators(in: Syntax(sequence))
        if !symbols.isDisjoint(with: Self.comparisonOperators) {
            comparisons.append(ExprSyntax(sequence))
        }
        if isFraction(Syntax(sequence)) {
            hasFraction = true
            if firstArithmeticSite == nil { firstArithmeticSite = Syntax(sequence) }
        }
    }

    /// A comparison counts only when it is *deciding something computed* — either a side does
    /// arithmetic (`progress - lastReported >= 0.01`) or a side is a value the kernel derived
    /// (`index < totalChunks`). A bare `status == .ok` decides nothing a generator could break.
    func governingComparisonReferencing(_ bindings: [String]) -> Bool {
        let derived = Set(bindings)
        return comparisons.contains { comparison in
            let node = Syntax(comparison)
            if containsArithmetic(node) { return true }
            return references(node, anyOf: derived)
        }
    }

    // MARK: - Syntactic predicates

    private func operators(in node: Syntax) -> Set<String> {
        var found: Set<String> = []
        for token in node.tokens(viewMode: .sourceAccurate) {
            guard case .binaryOperator = token.tokenKind else { continue }
            found.insert(token.text)
        }
        return found
    }

    private func containsArithmetic(_ node: Syntax) -> Bool {
        !operators(in: node).isDisjoint(with: Self.arithmeticOperators)
    }

    /// `Double(a) / Double(b)` — a division with a numeric conversion in it. This is the progress
    /// shape, and every progress bug in this codebase is a case of it not reaching 1.0.
    private func isFraction(_ node: Syntax) -> Bool {
        guard operators(in: node).contains("/") else { return false }
        return node.tokens(viewMode: .sourceAccurate).contains { token in
            Self.pureConversions.contains(token.text)
        }
    }

    /// Any call that is not a numeric conversion refutes the binding. Conservative on purpose: the
    /// kernel must be arithmetic the rule can *see*, not a call it would have to trust.
    private func onlyPureCalls(_ node: Syntax) -> Bool {
        for call in node.children(viewMode: .sourceAccurate).compactMap({
            $0.as(FunctionCallExprSyntax.self)
        }) {
            let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
            guard let name, Self.pureConversions.contains(name) else { return false }
        }
        return node.children(viewMode: .sourceAccurate).allSatisfy { onlyPureCalls($0) }
    }

    private func references(_ node: Syntax, anyOf names: Set<String>) -> Bool {
        guard !names.isEmpty else { return false }
        return node.tokens(viewMode: .sourceAccurate).contains { names.contains($0.text) }
    }
}
