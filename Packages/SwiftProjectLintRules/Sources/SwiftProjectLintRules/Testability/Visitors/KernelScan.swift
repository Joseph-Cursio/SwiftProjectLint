import SwiftProjectLintModels
import SwiftSyntax

/// What the body contains, scored against the one question that matters: **is there arithmetic here
/// that governs a decision?**
///
/// Deliberately not a dataflow analysis. A kernel has no syntactic boundary — it is whatever set of
/// statements you *choose* to lift — so a precise "maximal pure set" is both hard and beside the
/// point: the reader draws the boundary, the rule only has to say *there is one here, and here is
/// what it is made of*. What the scan must get right is the **precision**, and precision comes from
/// demanding that arithmetic reach a governing position, not from tracing it exactly.
struct KernelScan {

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
    private var pathSpecificBindings: [String] = []
    private var bodyMentionsAPath = false

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
        pathSpecificBindings = collector.pathSpecificBindings
        bodyMentionsAPath = PathEvidence.occurs(in: Syntax(body))
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

    var signalCount: Int {
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
        if !isArithmeticKernel, isPathKernel {
            // `.normalizer` is "derives one value from another in the same domain… owes a
            // round-trip and an idempotent normalisation". Without path-specific evidence the
            // shape does not entail that: `output.split(maxSplits: 1)` leaves the same domain,
            // and `path.lowercased()` is idempotent but lossy, so it cannot round-trip. Claiming
            // the role anyway would put a derivation in the seed manifest under a law it does not
            // owe. `nil` is the same answer a fraction-only kernel gets, for the same reason —
            // inventing a role to fill the field is worse than leaving it empty.
            return hasPathSpecificEvidence ? .normalizer : nil
        }
        return hasSlicingArithmetic ? .partition : nil
    }

    /// What a derived string that governs a decision owes when nothing says it is a *path*.
    ///
    /// Deliberately does not choose between round-trip and idempotence, because the corpus shows
    /// both shapes here and the gate cannot tell them apart: `output.split(maxSplits: 1)` into a
    /// name and a body owes that the parts rejoin to the whole; `path.lowercased()` used as a
    /// dedup key owes idempotence and does **not** round-trip, lowercasing being lossy. Naming
    /// both as conditional is weaker than the path arm's advice and is the honest strength.
    ///
    /// What it does state unconditionally is the boundary set, because that is what actually
    /// catches these: `"a\n".components(separatedBy: "\n").count` is 2, a `split(maxSplits: 1)`
    /// on input with no separator yields one part where the reader expected two, and a trailing
    /// separator is the difference between every off-by-one in this shape and none.
    static let stringDerivationLaw =
        "the derivation should be TOTAL over the strings it names — an answer, not a trap or a "
        + "wrong one, for the empty string, for input with no separator, for a separator at the "
        + "very end, and for repeated separators. Then whichever applies: if it cuts a whole into "
        + "parts, the parts should RECOMBINE into what you started with; if it canonicalises, it "
        + "should be IDEMPOTENT. Note these are not both true of every derivation — a lossy "
        + "canonicalisation like `lowercased()` is idempotent and does not round-trip."

    static let stringDerivationSuggestion =
        "Extract the derivation into a free function over the strings alone, named for what it "
        + "produces rather than for the method it came from. Strings in, strings out is "
        + "constructible in a test with no I/O, which is the whole point: the boundary cases above "
        + "can then be generated against rather than eyeballed. Do NOT lift the decision this "
        + "feeds — a `Set.contains` or a `count >` is already correct by construction, and the law "
        + "is over the value being DERIVED, not over the test applied to it."

    /// Named when only *some* of the bindings are path-derived, because the root law is not
    /// about the others and the summary lists them all.
    ///
    /// `EditTools.swift:120` is the measured case: `parent = url.deletingLastPathComponent()`
    /// beside `lineCount = content.components(separatedBy: "\n").count`. Two unrelated
    /// derivations in one method, one finding, and a reader told to check round-trip from a root
    /// is being told it about a line count. The empty string for the whole-shape case keeps the
    /// message unchanged where the advice was already exactly right.
    private var mixedShapeCaveat: String {
        // Silent unless the path evidence is attached to *named bindings* and covers only some of
        // them. When the evidence is elsewhere in the body — `scanSync`, whose bindings are all
        // generic string operations and whose `lastPathComponent` is on the following line —
        // there is no subset to name, and guessing one would be worse than saying nothing.
        guard !pathSpecificBindings.isEmpty,
              pathSpecificBindings.count < derivedPathBindings.count else { return "" }
        let named = pathSpecificBindings.prefix(3).map { "`\($0)`" }.joined(separator: ", ")
        return " That law is over \(named); the other names here derive strings that are not "
            + "paths, and what those owe is totality at the boundaries — the empty string, no "
            + "separator, a trailing separator."
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

    /// Whether the derivation used an operation that identifies a **path**, which is what
    /// licenses advice about a root.
    ///
    /// The gate for the shape is a *string* derivation that governs a decision, and the advice
    /// used to talk about a path under a root regardless. Measured over 26 repositories: of the
    /// six findings on this arm, two derived no path at all — `path.lowercased()` used as a
    /// dedup key, and `output.split(separator: "\n", maxSplits: 1)` cut into a name and a body.
    /// Telling a reader to check round-trip *from the root* at either is advice specific enough
    /// to follow and pointing at nothing.
    ///
    /// This is not hypothetical. `AgentRunner+ProjectGuidance.swift:14` carried the path advice
    /// naming a binding called `url`, while the kernel two lines below was a byte budget whose
    /// guard counted UTF-8 bytes and whose truncation counted `Character`s — a 16 KB cap that
    /// passed 410 KB of emoji. A reader who wrote the suggested round-trip laws would have proved
    /// something true about `url` and walked past the bug.
    private var hasPathSpecificEvidence: Bool { bodyMentionsAPath }

    var law: String {
        if !isArithmeticKernel, isPathKernel {
            guard hasPathSpecificEvidence else { return Self.stringDerivationLaw }
            return "the derivation should ROUND-TRIP — rebuilding the whole from the root and the "
                + "derived part should give back what you started with — and normalising should be "
                + "IDEMPOTENT: applying it twice must equal applying it once. Both are checkable "
                + "over generated roots and paths, and both are where off-by-one prefix bugs live."
                + mixedShapeCaveat
        }
        if hasFraction, hasSlicingArithmetic {
            return "the parts should tile the whole exactly, and progress should terminate at 1.0 — "
                + "including for an empty input."
        }
        if hasFraction {
            return "progress should be monotonic, stay within 0...1, and terminate at 1.0 — "
                + "including for an empty input."
        }
        guard hasSlicingArithmetic else { return Self.boundedComparisonLaw }
        return "the parts should tile the whole exactly — no gap, no overlap — and the count should "
            + "be exactly `ceil(total / size)`."
    }

    /// What arithmetic that governs a **comparison** owes, as opposed to arithmetic that cuts a
    /// whole into parts.
    ///
    /// The tiling law used to be the fallback for the arithmetic shape, claimed whenever there was
    /// no fraction — including where `hasSlicingArithmetic` is false, which is exactly when `role`
    /// declines to say `.partition`. **The two disagreed inside this type**: the seed manifest said
    /// "I will not call this a partition" while the message told the reader it owed a tiling.
    ///
    /// Measured over the 26-repository corpus: **7 of 20 findings** were on this branch. None of
    /// them cuts anything up. `GitCloneHelper.listSwiftFiles` derives `maxFileSize = 512 * 1_024`
    /// and compares a file size against it — a threshold. `SnapshotManager.computeDiff` derives
    /// `summary.totalTypes - snapshot.typeCount` and four siblings — a difference, whose real law
    /// is antisymmetry and a zero at equality, and whose real bug is iterating one side's keys
    /// instead of the union. `ToolInvocation.requireValue` derives `index + 1` and bounds-checks
    /// it. "The count should be exactly `ceil(total / size)`" is not a statement about any of them.
    static let boundedComparisonLaw =
        "the derivation should be TOTAL — an answer for every input the types admit, including an "
        + "empty collection, a zero bound, and a negative difference — and the decision it governs "
        + "should be right AT the boundary, which is where the off-by-one lives: a value exactly "
        + "equal to the bound, a count of zero, a count of one. If it is a difference of two "
        + "measurements, it also owes ANTISYMMETRY — swapping the operands negates it — and zero "
        + "when they agree."

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
            guard hasPathSpecificEvidence else { return Self.stringDerivationSuggestion }
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
            return "Extract the arithmetic into a free function or value type constructed from "
                + "those inputs alone, so the boundary cases can be generated against rather than "
                + "eyeballed. The method keeps the I/O and asks the value type for the answer."
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
