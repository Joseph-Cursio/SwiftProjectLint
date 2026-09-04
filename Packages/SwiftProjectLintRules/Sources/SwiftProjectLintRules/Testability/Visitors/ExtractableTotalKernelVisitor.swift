import Foundation
import SwiftProjectLintModels
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
/// - **A derivation must feed a decision.** A derived value that is merely *stored* is not a kernel
///   — it has to govern something: a loop bound, an index, a slice range, a comparison, or a
///   progress fraction. This is the clause that separates chunking math from a local variable
///   someone extracted for readability, and it is why `navigateUp`'s pure path arithmetic is
///   deliberately *not* reported here (its result is assigned, not used as a bound) — that shape is
///   a state-machine law, and it belongs to a different template.
///
/// ## Two shapes, because one of them was found by the rule scoring zero
///
/// The gates above describe the **arithmetic** shape. It was the only shape for as long as the rule
/// was only ever pointed at an app whose bugs were chunking math — and then the rule was run over a
/// 60k-line linter and reported **nothing at all**. Not "this code is clean": the linter's impure
/// methods enumerate directories and derive paths, and a path kernel has no operator reaching a
/// bound, so every gate walked past it. `dropFirst(prefix.count)` is a slice with no arithmetic in
/// it anywhere.
///
/// So there is a second shape: a **path/string derivation that governs a decision**. Two strings
/// derived and chained, then used to slice, to compare, or to look up. Its law is a round-trip and
/// an idempotent normalisation rather than a tiling, and its bugs are off-by-one prefixes rather
/// than off-by-one counts — including both of the bugs this project's own property-test road test
/// found.
///
/// Admitting it narrows the third gate rather than widening it: a derived *display string* still
/// does not fire, because it governs nothing. What changed is that "governs" now includes deciding
/// with a string, not only bounding a loop with a number.
///
/// `info` severity; opt-in. Reports a refactor, not a defect.
final class ExtractableTotalKernelVisitor: BasePatternVisitor {

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
            message: "A total kernel is trapped in this impure method — \(kernel.summary) depend "
                + "only on its parameters and locals, and nothing else in the method reaches them. "
                + "Lift them into a value type and they become property-testable: \(kernel.law)",
            filePath: getFilePath(for: Syntax(kernel.anchor)),
            lineNumber: getLineNumber(for: Syntax(kernel.anchor)),
            suggestion: kernel.suggestion,
            ruleName: .extractableTotalKernel,
            symbol: node.name.text,
            role: kernel.role
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

    /// A mutable index seeded from outside the kernel — `var index = current.queuedChunks` — that
    /// then drives the slice. The resume point, and the thing a cold reader lifted as a separate
    /// scalar rather than folding into the tiler where its clamp belongs. (B18.)
    private var hasResumableIndex = false

    /// A local bound to a **path or string derivation** — `let prefix = root.hasSuffix("/") ? root
    /// : root + "/"`, `let relative = String(path.dropFirst(prefix.count))`.
    ///
    /// The second kernel shape, and the one this rule was blind to. Scoring **zero** on a 60k-line
    /// linter is what exposed it: the arithmetic gate wants an operator reaching a bound or a
    /// fraction, and a path kernel has neither — it derives one string from another and then
    /// *decides* with it. `dropFirst(prefix.count)` is a slice with no arithmetic operator in it at
    /// all, so every gate here read it as ordinary string handling.
    ///
    /// It is not ordinary. This is the shape both of this project's own property-test bugs had: a
    /// `.swift` suffix stripped with `replacingOccurrences` rather than from the end, and a
    /// directory exclusion that did not round-trip. Both are laws over `(root, path) -> relative`,
    /// and both were unreachable from a test because the derivation was welded to a `FileManager`
    /// enumeration.
    private var derivedPathBindings: [String] = []

    /// `dropFirst(prefix.count)` — a slice driven by a **count** rather than by an arithmetic
    /// expression. `hasSlicingArithmetic` requires an operator, so it does not see this.
    private var hasCountDrivenSlice = false

    /// A derived name used in a membership test — `skippedDirectories.contains(dirName)`.
    ///
    /// This is the governing use that **classification** kernels have and arithmetic ones do not,
    /// and admitting it is a deliberate narrowing of the rule's third gate. That gate excluded
    /// classification wholesale, on the grounds that a derived *display string* governs nothing.
    /// That is right for a string which is merely stored or returned — and wrong for one that then
    /// decides whether to prune a subtree.
    private var hasGoverningMembershipTest = false

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
        hasResumableIndex = collector.hasResumableIndex

        derivedPathBindings = collector.derivedPathBindings
        hasCountDrivenSlice = collector.hasCountDrivenSlice
        hasGoverningMembershipTest =
            collector.membershipTestReferences(collector.derivedPathBindings)
            || collector.comparisonReferences(collector.derivedPathBindings)

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
    var isWorthExtracting: Bool { isArithmeticKernel || isPathKernel }

    private var isArithmeticKernel: Bool {
        let hasArithmetic = !derivedBindings.isEmpty || hasFraction
        let governs = hasGoverningComparison || hasSlicingArithmetic || hasFraction
        return hasArithmetic && governs && signalCount >= 2
    }

    /// The same conjunction as the arithmetic shape, in the string domain: a value **derived** and
    /// then used to **decide**.
    ///
    /// **The governing clause is what earns the precision here, not the count.** Measured: relaxing
    /// `>= 2` to `>= 1` changes nothing on either corpus below — one derived string almost never
    /// reaches a slice or a membership test on its own. The threshold stays as a cheap guard for
    /// codebases unlike these two, but it should not be credited with the filtering.
    ///
    /// The governing test is deliberately stricter than the arithmetic shape's. That one accepts
    /// any comparison containing an arithmetic operator, regardless of which names it mentions;
    /// `+` on strings is concatenation, so reusing it here vouched for derivations it had nothing
    /// to do with. `comparisonReferences` requires the comparison to actually name the binding.
    private var isPathKernel: Bool {
        derivedPathBindings.count >= 2 && (hasCountDrivenSlice || hasGoverningMembershipTest)
    }

    private var signalCount: Int {
        var count = derivedBindings.count
        if hasFraction { count += 1 }
        if hasGoverningComparison { count += 1 }
        if hasSlicingArithmetic { count += 1 }
        return count
    }

    /// What this kernel **is**, for the seed manifest.
    ///
    /// Only claimed where the shape actually entails it. A tiler — slicing arithmetic mapping an
    /// index to a part — is a `partition`, and a partition owes a tiling by virtue of being one;
    /// that is a law a correct implementation cannot fail, which is what makes it worth carrying.
    /// The path shape is a `normalizer`: its round-trip and idempotence are real but conjectured,
    /// and the manifest says so rather than overclaiming.
    ///
    /// A fraction-only kernel gets `nil`. Progress arithmetic is a kernel worth extracting, but
    /// "monotone and terminates at 1.0" is not one of the roles this vocabulary names, and inventing
    /// a role to fill the field would be worse than leaving it empty.
    var role: PBTSeedRole? {
        if !isArithmeticKernel, isPathKernel { return .normalizer }
        return hasSlicingArithmetic ? .partition : nil
    }

    var summary: String {
        if !isArithmeticKernel, isPathKernel {
            return derivedPathBindings.prefix(3).map { "`\($0)`" }.joined(separator: ", ")
        }
        guard !derivedBindings.isEmpty else { return "the progress fraction here" }
        let named = derivedBindings.prefix(3).map { "`\($0)`" }.joined(separator: ", ")
        // Only mention the fraction separately when it is not already one of the names — otherwise
        // the message reads "`progress` and the progress fraction".
        return hasUnnamedFraction ? "\(named) and the progress fraction" : named
    }

    var law: String {
        if !isArithmeticKernel, isPathKernel {
            return "the derivation should ROUND-TRIP — rebuilding the whole from the root and the "
                + "derived part should give back what you started with — and normalising should be "
                + "IDEMPOTENT: applying it twice must equal applying it once. Both are checkable "
                + "over generated roots and paths, and both are where off-by-one prefix bugs live."
        }
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

    /// What to actually build — and for a **tiler**, the shape matters as much as the fact.
    ///
    /// *"Extract the arithmetic into a value type"* is not wrong, but it is under-specified in the one
    /// case where the reader has a real choice, and cold-reader walks measured the cost: given
    /// chunking math, readers reliably lift the **count** — `func chunkCount(...) -> Int` — because a
    /// scalar is the most obvious "arithmetic." A count is a fine pure function, but it is **not a
    /// tiler**: no law over it says the parts tile the whole, and the property that actually catches
    /// the resume-counter and empty-payload bugs (a `partition` over an index → slice map) never gets
    /// proposed for it. The bug is one method away and the reader walks past it.
    ///
    /// So when slicing arithmetic is present, name the shape that carries the tiling law: a method
    /// mapping a part **index** to its slice (or byte range) of the whole. That is the extraction that
    /// pays; the count comes along for free as a property of it.
    ///
    /// **B18 — and when the tiler has a resume point, name that too.** Naming the tiler shape moved
    /// the resume-counter bug from 1/3 to 2/3 in a cold-reader walk; the miss that held it there was a
    /// reader who lifted the *resume index* — `var index = current.queuedChunks` — as its own scalar
    /// `func resumeIndex(...) -> Int`, a shape that carries no tiling law and drew them straight past
    /// the bug at the right line. The resume point is not a kernel of its own: it is the tiler's
    /// clamped `startIndex`. When an externally-seeded index drives the slice, say so — but *only*
    /// then, so a plain `var i = 0` tiler with no resume concept keeps the shorter advice.
    var suggestion: String {
        if !isArithmeticKernel, isPathKernel {
            return "Extract the derivation into a free function or value type over the strings "
                + "alone — `func relativePath(of item: String, under root: String) -> String` — and "
                + "let the method keep the enumeration and ask it what to call each item. Two "
                + "strings in, one string out is constructible in a test with no disk, which is the "
                + "whole point: the prefix handling can then be generated against rather than "
                + "eyeballed. Do NOT lift the membership check on its own — a `Set.contains` is "
                + "already correct by construction, and the law is over the value being CLASSIFIED, "
                + "not over the lookup."
        }
        guard hasSlicingArithmetic else {
            return "Extract the arithmetic into a value type constructed from those inputs alone. "
                + "The method keeps the I/O and asks the value type where the bytes are."
        }
        var advice = "Extract a value type whose key method maps a part INDEX to its slice of the "
            + "whole — `func chunk(of whole: …, at index: Int) -> …` returning the part, or "
            + "`func byteRange(ofChunk index: Int) -> Range<Int>` returning where it lives. THAT "
            + "method carries the tiling law (the parts reassemble the whole, and an out-of-range "
            + "index yields nothing rather than trapping); a bare chunk *count* does not, and is the "
            + "extraction that walks past the bug. The method keeps the I/O and asks the value type "
            + "where the bytes are."
        if hasResumableIndex {
            advice += " And the point this loop RESUMES from — the index seeded from outside, not a "
                + "literal `0` — is not a kernel of its own: do not lift it as a separate "
                + "`func resumeIndex(...) -> Int`, which carries no tiling law and leaves the bug at "
                + "the site. It is the tiler's `startIndex`, and it belongs INSIDE the value type, "
                + "clamped to `0...count` at construction — an unclamped start from a server counter "
                + "either traps (negative) or silently completes a partial upload (too large), and "
                + "the clamp is the property the tiler owes."
        }
        return advice
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

    /// A `var` whose initialiser is not an integer literal — a mutable value seeded from *outside*
    /// the kernel, e.g. `var index = current.queuedChunks`. A `var i = 0` is excluded: a literal
    /// seed has no resume concept and no clamp to owe.
    private var externallySeededVars: Set<String> = []

    /// Identifiers that appear inside slicing arithmetic — `index` and `chunkSize` in
    /// `dropFirst(index * chunkSize)`. The intersection with `externallySeededVars` is the resume
    /// index: a value sourced from outside that drives the slice.
    private var slicingIndexNames: Set<String> = []

    /// A resumable index is present when an externally-seeded `var` is the thing driving the slice.
    /// (B18.) This implies `hasSlicingArithmetic`, since `slicingIndexNames` is only ever populated
    /// alongside it.
    var hasResumableIndex: Bool {
        !externallySeededVars.isDisjoint(with: slicingIndexNames)
    }

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

    // MARK: - The path/string shape

    private(set) var derivedPathBindings: [String] = []
    private(set) var hasCountDrivenSlice = false

    /// Identifiers passed to a membership test — `dirName` in `skipped.contains(dirName)`.
    private var membershipArguments: Set<String> = []

    /// Calls that derive one string from another and nothing else. Every entry is total and
    /// allocation-only: none of them reads the disk, the clock or global state, so a binding built
    /// from them is a value the reader could have written by hand.
    ///
    /// `contains` is absent on purpose. It is the membership *test*, tracked separately as a
    /// governing use — counting it as a derivation too would let one expression satisfy both
    /// halves of the conjunction and collapse the gate.
    private static let pathCalls: Set<String> = [
        "hasPrefix", "hasSuffix", "starts", "dropFirst", "dropLast", "prefix", "suffix",
        "lowercased", "uppercased", "capitalized", "trimmingCharacters", "replacingOccurrences",
        "components", "split", "joined", "appendingPathComponent", "appendingPathExtension",
        "deletingLastPathComponent", "deletingPathExtension", "standardizingPath"
    ]

    /// Property reads that are part of a derivation rather than a call — `path.lastPathComponent`.
    private static let pathMembers: Set<String> = [
        "lastPathComponent", "pathExtension", "deletingLastPathComponent", "deletingPathExtension",
        "standardizedFileURL", "absoluteString", "count", "isEmpty"
    ]

    /// Wrappers that change a string's static type without computing anything.
    private static let pathConversions: Set<String> = [
        "String", "Substring", "NSString", "URL", "Character"
    ]

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
                    slicingIndexNames.formUnion(identifiers(in: Syntax(subscriptCall.arguments)))
                }
            }
            walk(child)
        }
    }

    /// `let totalChunks = (data.count + chunkSize - 1) / chunkSize` — arithmetic, no opaque calls.
    ///
    /// Also notes a **`var` seeded from a non-literal** — `var index = current.queuedChunks` — as an
    /// externally-sourced mutable index (B18), independent of whether its initialiser does
    /// arithmetic; the resume seed usually does none.
    private mutating func record(_ declaration: VariableDeclSyntax) {
        let isVar = declaration.bindingSpecifier.tokenKind == .keyword(.var)
        for binding in declaration.bindings {
            guard let value = binding.initializer?.value,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
                continue
            }
            if isVar, !value.is(IntegerLiteralExprSyntax.self) {
                externallySeededVars.insert(name)
            }
            guard containsArithmetic(Syntax(value)), onlyPureCalls(Syntax(value)) else {
                recordPathDerivation(name, value: value, at: declaration)
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

    /// A binding that derives a string from other strings — reached only when the arithmetic test
    /// has already declined, so the two shapes never both claim one binding.
    ///
    /// Note this catches `let prefix = root.hasSuffix("/") ? root : root + "/"`, which the
    /// arithmetic path sees and rejects: `+` reads as an arithmetic operator, then `onlyPureCalls`
    /// refuses `hasSuffix`. Falling through to here is what turns that rejection into a finding
    /// instead of a silence.
    private mutating func recordPathDerivation(
        _ name: String, value: ExprSyntax, at declaration: VariableDeclSyntax
    ) {
        guard containsPathOperation(Syntax(value)), onlyPathSafeCalls(Syntax(value)) else { return }
        derivedPathBindings.append(name)
        if firstArithmeticSite == nil { firstArithmeticSite = Syntax(declaration) }
    }

    private mutating func record(_ call: FunctionCallExprSyntax) {
        guard let callee = call.calledExpression.as(MemberAccessExprSyntax.self) else { return }
        let name = callee.declName.baseName.text
        let arguments = Syntax(call.arguments)
        if Self.slicingCalls.contains(name), containsArithmetic(arguments) {
            hasSlicingArithmetic = true
            slicingIndexNames.formUnion(identifiers(in: arguments))
            if firstArithmeticSite == nil { firstArithmeticSite = Syntax(call) }
            return
        }
        // `dropFirst(prefix.count)` — a slice with no operator in it, and the exact expression the
        // arithmetic gate above walks past.
        if Self.slicingCalls.contains(name), referencesCount(arguments) {
            hasCountDrivenSlice = true
            if firstArithmeticSite == nil { firstArithmeticSite = Syntax(call) }
            return
        }
        // `skippedDirectories.contains(dirName)` — the governing use a classification kernel has.
        // A trailing-closure form (`contains(where:)`) is `pureClosureCandidate`'s finding, so only
        // the value form counts here.
        if name == "contains", call.trailingClosure == nil {
            membershipArguments.formUnion(identifiers(in: arguments))
        }
    }

    /// Whether the expression reads a `.count` — what makes `dropFirst(prefix.count)` a derived
    /// slice rather than a constant one. `dropFirst(1)` is not a kernel.
    private func referencesCount(_ node: Syntax) -> Bool {
        node.children(viewMode: .sourceAccurate).contains { child in
            if let member = child.as(MemberAccessExprSyntax.self),
               member.declName.baseName.text == "count" {
                return true
            }
            return referencesCount(child)
        }
    }

    /// Whether any of these derived names is the subject of a membership test.
    func membershipTestReferences(_ names: [String]) -> Bool {
        !membershipArguments.isDisjoint(with: Set(names))
    }

    /// A comparison that names one of these bindings — `parent == current`.
    ///
    /// Strictly `references`, with no `containsArithmetic` shortcut. That shortcut is right for the
    /// arithmetic shape, where any computed comparison is evidence, and wrong here: `+` on strings
    /// is concatenation, so a single `message + suffix` anywhere in the body would vouch for a
    /// derivation it has nothing to do with. Writing the loose version first and then finding it
    /// fired on unrelated bindings is what produced this method.
    func comparisonReferences(_ names: [String]) -> Bool {
        let derived = Set(names)
        return comparisons.contains { references(Syntax($0), anyOf: derived) }
    }

    private func containsPathOperation(_ node: Syntax) -> Bool {
        for child in node.children(viewMode: .sourceAccurate) {
            if let member = child.as(MemberAccessExprSyntax.self) {
                let name = member.declName.baseName.text
                if Self.pathCalls.contains(name) || Self.pathMembers.contains(name) { return true }
            }
            if containsPathOperation(child) { return true }
        }
        return false
    }

    /// Every call in the subtree must be a known string derivation or a type conversion. Same
    /// posture as `onlyPureCalls`: the rule will not vouch for work it cannot see, so one unknown
    /// helper call disqualifies the binding.
    private func onlyPathSafeCalls(_ node: Syntax) -> Bool {
        for child in node.children(viewMode: .sourceAccurate) {
            if let call = child.as(FunctionCallExprSyntax.self) {
                if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
                    guard Self.pathCalls.contains(member.declName.baseName.text) else { return false }
                } else if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
                    let name = reference.baseName.text
                    guard Self.pathConversions.contains(name) || Self.pureConversions.contains(name)
                    else { return false }
                } else {
                    return false
                }
            }
            guard onlyPathSafeCalls(child) else { return false }
        }
        return true
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

    /// The bare identifiers appearing in a slice expression — `index`, `chunkSize` in
    /// `dropFirst(index * chunkSize)`. Used to find which names actually drive a slice. (B18.)
    private func identifiers(in node: Syntax) -> Set<String> {
        var found: Set<String> = []
        for token in node.tokens(viewMode: .sourceAccurate) {
            if case .identifier = token.tokenKind { found.insert(token.text) }
        }
        return found
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
