import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor: flags **two name lists that almost agree** — a strong sign they
/// are meant to be the same enumeration, maintained in two places, with one now missing
/// entries the other has. See `Docs/rules/parallel-list-drift.md`.
///
/// This is the complement of `ParallelEnumShape`, which fires on an *exact* case-set
/// match ("same concept modeled twice"). This rule fires on a *near* match ("same
/// concept, and they have drifted"), which is the actionable bug: adding an entry to one
/// list and forgetting the other is not a compile error. It is the cross-file payoff of
/// the single-file `ManualRegistrationList`, which flags the hazardous *shape*; this one
/// flags a list that has already lost the race.
///
/// **Phase 1 (walk).** Catalogs every "name list" from four carriers:
///   1. `enum` case names,
///   2. array literals whose elements are uniformly name-like (string literals,
///      leading-dot members, or type references),
///   3. runs of consecutive registration calls (`register…`/`add…`/…) from which a
///      distinguishing name can be read — the shape of `BuiltInRules.registerAll`,
///   4. member runs — one operation applied to a run of one value's members
///      (`MemberRunReader`), compared only with each other.
///
/// **Phase 2 (`finalizeAnalysis`).** Names are normalized (case- and separator-free) so
/// `UIPatterns`, `uiPatterns` and `"ui-patterns"` compare equal. An inverted index yields
/// candidate pairs sharing at least `minShared` entries; a pair fires when its Jaccard
/// similarity clears `minSimilarity` but falls short of 1.0. One issue is emitted per
/// *side that is missing entries*, so a strict subset reports only at the deficient list.
final class ParallelListDriftVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    // MARK: - Tunables

    /// The *longer* list of a pair must reach this length before the pair is considered:
    /// it establishes that there is a substantial enumeration in play. Deliberately not
    /// applied to both sides — a list that has drifted *down* to two or three entries is
    /// the deficient one, and gating on its own length would silence exactly the finding
    /// worth reporting.
    private static let minEntries = 4
    /// A pair must genuinely overlap before "they should match" is a plausible reading.
    /// This, not per-list length, is the real guard against coincidental agreement, and
    /// it doubles as the collection floor — a list of fewer entries can never reach it.
    private static let minShared = 3
    /// Jaccard floor. 0.6 admits e.g. 6-of-8 agreement while rejecting incidental overlap.
    private static let minSimilarity = 0.6
    /// A stricter floor for a **strict subset** — a pair where one list is wholly contained in
    /// the other. A subset is far weaker evidence of drift than mutual divergence: a curated
    /// "the few we support" list is a subset of a canonical one *by design*, not by mistake. At
    /// >= 0.8 the subset is missing only about one entry of a substantial list — the genuine
    /// "forgot to add the new entry" case — whereas a curated subset omits a larger fraction and
    /// is suppressed. Mutual divergence (each list holds something the other lacks) keeps the
    /// base `minSimilarity`. Measured: SwiftCompilerFlagStudio produced 11 three-entry
    /// `.enumeration([...])` value lists, each flagged at 0.75 against one four-entry canonical
    /// list — all false positives.
    private static let subsetSimilarity = 0.8
    /// A member run is reported only when this many other runs agree **exactly** on the family it
    /// falls short of. One superset is weak evidence: a type's members are selected from for many
    /// reasons, and over 40 repositories most single-superset findings were two gates that test
    /// different flags of one value on purpose — `summary.isStatic` here, `summary.isMutating`
    /// there. Two places that agree on the whole family, and a third that is one short, is the
    /// shape a forgotten member leaves: SwiftLintRuleStudio's two `collectAllRuleIds` against an
    /// import check missing `analyzerRules`.
    private static let memberRunCorroboration = 2
    /// A name appearing in more than this many lists is a generic word (`name`, `value`),
    /// not a distinguishing entry. Ignoring it for candidate generation also bounds the
    /// pair count, keeping Phase 2 near-linear instead of quadratic in list count.
    private static let maxFanout = 40

    // MARK: - Model

    /// Which syntactic shape a list was read from — reported so the message says
    /// *where* to go and fix it.
    private enum Carrier: String {
        case enumCases = "enum"
        case arrayLiteral = "array"
        case callRun = "registration run"
        case memberRun = "member run"
    }

    private struct NameList {
        let owner: String                  // `PatternCategory`, `packs`, `registerFactory(…)`
        let carrier: Carrier
        let names: Set<String>             // normalized
        let display: [String: String]      // normalized → original spelling
        let file: String
        let line: Int
        /// For a member run, the members read by one operation — see `MemberRunReader.Run`.
        let core: Set<String>

        /// Original spellings for `names`, sorted, for use in messages.
        func spellings(of subset: Set<String>) -> [String] {
            subset.map { display[$0] ?? $0 }.sorted()
        }
    }

    private var lists: [NameList] = []

    // MARK: - Phase 1: carrier 1 — enum cases

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        // Unlike `ParallelEnumShape`, associated values are *not* disqualifying: this rule
        // compares the roster of names, and `case failure(Error)` still contributes the
        // name `failure` that a parallel list is expected to carry.
        //
        // A tagged union over *types* is the exception, and it is a different shape rather than a
        // threshold on the same one. When the case names ARE their payloads' type names —
        // `bool(Bool)`, `int(Int)`, `int8(Int8)` — the roster is not a vocabulary anybody chose;
        // it is Swift's scalar types, spelled once per case because the enum is a value tree over
        // them. Comparing that against a list of type names finds an overlap guaranteed by the
        // language, which is what `MinimalCodableValue` against `RawType` was (#190).
        //
        // `failure(Error)` keeps contributing, because `failure` is not `Error`.
        guard !Self.isTaggedUnionOverTypes(node) else { return .visitChildren }

        let names = node.memberBlock.members.flatMap { member -> [String] in
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { return [] }
            return caseDecl.elements.map(\.name.text)
        }
        record(names, owner: node.name.text, carrier: .enumCases, node: Syntax(node))
        return .visitChildren
    }

    /// Whether the enum's cases name their own payload types — a value tree rather than a
    /// vocabulary.
    ///
    /// Judged on a **majority** of the payload-carrying cases, so one odd constructor does not
    /// decide it, and it requires at least two such cases: a single `int(Int)` is a coincidence,
    /// not a shape.
    static func isTaggedUnionOverTypes(_ node: EnumDeclSyntax) -> Bool {
        let elements = node.memberBlock.members
            .compactMap { $0.decl.as(EnumCaseDeclSyntax.self) }
            .flatMap(\.elements)

        let withPayload = elements.filter { $0.parameterClause?.parameters.count == 1 }
        guard withPayload.count >= 2 else { return false }

        let echoing = withPayload.filter { element in
            guard let parameter = element.parameterClause?.parameters.first else { return false }
            let payload = parameter.type.trimmedDescription
            return payload.lowercased() == element.name.text.lowercased()
        }
        return echoing.count * 2 > withPayload.count
    }

    // MARK: - Phase 1: carrier 2 — array literals

    override func visit(_ node: ArrayExprSyntax) -> SyntaxVisitorContinueKind {
        if let run = MemberRunReader.run(inArrayLiteral: node) {
            recordMemberRun(run)
            return .visitChildren
        }
        guard let names = NameListReader.names(inArrayLiteral: node) else { return .visitChildren }
        record(names, owner: NameListReader.bindingName(of: node) ?? "array literal",
               carrier: .arrayLiteral, node: Syntax(node))
        return .visitChildren
    }

    // MARK: - Phase 1: carrier 3 — registration-call runs

    override func visit(_ node: CodeBlockItemListSyntax) -> SyntaxVisitorContinueKind {
        collectCallRuns(in: node)
        MemberRunReader.runs(inStatements: node).forEach(recordMemberRun)
        return .visitChildren
    }

    // MARK: - Phase 1: carrier 4 — member runs

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        MemberRunReader.runs(inLogicalChain: node).forEach(recordMemberRun)
        return .visitChildren
    }

    override func visit(_ node: ConditionElementListSyntax) -> SyntaxVisitorContinueKind {
        MemberRunReader.runs(inConditions: node).forEach(recordMemberRun)
        return .visitChildren
    }

    /// One operation applied to a run of one value's members — see `MemberRunReader`.
    private func recordMemberRun(_ run: MemberRunReader.Run) {
        let place = MemberRunReader.enclosingDeclarationName(of: run.node).map { " in \($0)" } ?? ""
        record(run.members, owner: "\(run.base)\(place)", carrier: .memberRun, node: run.node, core: run.core)
    }

    /// Scan a statement list for maximal runs of consecutive registration calls to the
    /// *same* callee, each contributing a readable name. Mirrors the run detection in
    /// `ManualRegistrationListVisitor` — that rule flags the shape, this one reads the
    /// roster out of it.
    private func collectCallRuns(in list: CodeBlockItemListSyntax) {
        var runCallee: String?
        var runNames: [String] = []
        var runStart: CodeBlockItemSyntax?

        func flush() {
            if let callee = runCallee, let start = runStart {
                record(runNames, owner: "\(callee)(…)", carrier: .callRun, node: Syntax(start))
            }
            runCallee = nil
            runNames = []
            runStart = nil
        }

        for item in list {
            guard let (call, name) = runEntry(in: item) else {
                flush()
                continue
            }
            let callee = call.calledExpression.trimmedDescription
            if callee == runCallee {
                runNames.append(name)
            } else {
                flush()
                runCallee = callee
                runNames = [name]
                runStart = item
            }
        }
        flush()
    }

    /// One entry of a run, from either of the two shapes that carry a roster.
    ///
    /// The registration shape — `register("fetch")` — is the original, and is gated on
    /// `RegistrationVerb` so that arbitrary calls are not read as a list.
    ///
    /// The second shape has no verb to gate on and needs none, because its own signal is
    /// stronger: a run of sibling calls that each mention a **distinct leading-dot member**.
    ///
    /// ```swift
    /// Button("Rules")   { selection = .rules }
    /// Button("Reports") { selection = .reports }
    /// ```
    ///
    /// A menu built this way is an enumeration transcribed by hand, and it is exactly the carrier
    /// that was missing. The real instance: a title menu of eleven `Button`s against a twelve-case
    /// enum, silently omitting one destination. Written as `[.rules, .reports, …]` this rule
    /// reported it and named the missing case; written as eleven calls it saw nothing, because
    /// `Button` is not a registration verb and the first name-like argument is the *label*
    /// (`"Enabled Rule Violations"`), which normalizes nowhere near the case name it belongs to.
    ///
    /// Requiring a leading-dot member is what keeps this narrow. It is not "any run of calls with
    /// the same callee" — that would read every repeated view builder as a roster.
    private func runEntry(in item: CodeBlockItemSyntax) -> (FunctionCallExprSyntax, String)? {
        if let call = RegistrationVerb.call(in: item), let name = registeredName(from: call) {
            return (call, name)
        }
        guard case .expr(let expr) = item.item,
              let call = expr.as(FunctionCallExprSyntax.self),
              let name = leadingDotMemberName(in: call) else { return nil }
        return (call, name)
    }

    /// The single leading-dot member `call`'s **action closure** mentions, or `nil`.
    ///
    /// Only the trailing closure is searched, and that restriction is the whole precision of this
    /// carrier. A roster entry is what the item *does*, not how it is *styled*: reading arguments
    /// too collected `.red`, `.green` and `.primary` from lists of summary tiles, so two unrelated
    /// views drawing four tiles apiece paired on three shared colour names and reported drift
    /// against each other. Both were false positives, and both are gone with arguments excluded.
    ///
    /// Several members is as disqualifying as none: `Button("x") { mode = .a; other = .b }` names
    /// two things and cannot contribute one entry without choosing arbitrarily between them.
    private func leadingDotMemberName(in call: FunctionCallExprSyntax) -> String? {
        guard let closure = call.trailingClosure else { return nil }
        var found: Set<String> = []
        collectLeadingDotMembers(in: Syntax(closure), into: &found)
        return found.count == 1 ? found.first : nil
    }

    private func collectLeadingDotMembers(in node: Syntax, into found: inout Set<String>) {
        for child in node.children(viewMode: .sourceAccurate) {
            if let member = child.as(MemberAccessExprSyntax.self), member.base == nil {
                found.insert(member.declName.baseName.text)
            }
            collectLeadingDotMembers(in: child, into: &found)
        }
    }

    /// The distinguishing name a registration call contributes. Checks the trailing
    /// closure first — `registerFactory { _, _ in StateManagement(…) }` names its subject
    /// only in the closure body — then falls back to the first name-like argument.
    private func registeredName(from call: FunctionCallExprSyntax) -> String? {
        if let closure = call.trailingClosure,
           let last = closure.statements.last,
           case .expr(let expr) = last.item,
           let (name, _) = NameListReader.nameAndKind(of: expr) {
            return name
        }
        for argument in call.arguments {
            if let (name, _) = NameListReader.nameAndKind(of: argument.expression) { return name }
        }
        return nil
    }

    /// Adds a collected list, applying the length floor and dropping test/fixture files —
    /// a test that enumerates a deliberate subset is the rule's most common false positive.
    private func record(
        _ raw: [String],
        owner: String,
        carrier: Carrier,
        node: Syntax,
        core: Set<String> = []
    ) {
        guard !isTestOrFixtureFile() else { return }
        var names: Set<String> = []
        var display: [String: String] = [:]
        for original in raw {
            let key = NameListReader.normalize(original)
            guard !key.isEmpty else { continue }
            names.insert(key)
            if display[key] == nil { display[key] = original }
        }
        guard names.count >= Self.minShared else { return }
        lists.append(NameList(
            owner: owner,
            carrier: carrier,
            names: names,
            display: display,
            file: currentFilePath,
            line: getLineNumber(for: node),
            core: Set(core.map(NameListReader.normalize))
        ))
    }

    // MARK: - Phase 2: pair + emit

    /// The best counterpart found so far for one deficient list.
    private struct Match {
        let counterpart: Int
        let shared: Int
        let similarity: Double
    }

    func finalizeAnalysis() {
        // A list can drift against several counterparts at once — a stdlib type-name list
        // copied into four visitors pairs with all three of its siblings. Reporting every
        // pair buries the finding in near-duplicates, so each deficient list keeps only its
        // closest counterpart: the same fix (reconcile with the nearest list) resolves all
        // of them, and the remaining pairs re-surface on the next run if it does not.
        var best: [Int: Match] = [:]
        let memberRunAgreement = memberRunAgreementCounts()

        func offer(deficient: Int, counterpart: Int, shared: Int, similarity: Double) {
            let deficientNames = lists[deficient].names
            let counterpartNames = lists[counterpart].names
            // Only a list that is actually missing something is worth reporting.
            guard !counterpartNames.subtracting(deficientNames).isEmpty else { return }

            // A strict subset — the deficient list holds nothing the counterpart lacks — is weak
            // evidence of drift and needs the stricter `subsetSimilarity` floor. Mutual
            // divergence (the deficient list also has entries the counterpart lacks) is strong
            // evidence and keeps the base threshold already applied upstream.
            let deficientIsStrictSubset = deficientNames.subtracting(counterpartNames).isEmpty
            // Two member runs that each read something the other does not are, far more often
            // than drift, two different types sharing field names — `id`, `name`, `path` — or
            // two deliberately different selections from one. Only a run wholly contained in
            // another is the forgotten-member shape.
            if lists[deficient].carrier == .memberRun {
                // What the counterpart enumerated by one operation is what can be forgotten; a
                // member it reads beside that — a gate's `parameters.count == 1` beside its
                // `!isAsync && !isThrows` — is a different condition, not a missing entry.
                let missing = counterpartNames.subtracting(deficientNames)
                guard deficientIsStrictSubset,
                      missing.isSubset(of: lists[counterpart].core),
                      memberRunAgreement[counterpartNames, default: 0] >= Self.memberRunCorroboration
                else { return }
            }
            if deficientIsStrictSubset, similarity < Self.subsetSimilarity { return }

            let candidate = Match(counterpart: counterpart, shared: shared, similarity: similarity)
            guard let incumbent = best[deficient] else {
                best[deficient] = candidate
                return
            }
            if (candidate.similarity, candidate.shared) > (incumbent.similarity, incumbent.shared) {
                best[deficient] = candidate
            }
        }

        for (first, second) in candidatePairs() {
            let left = lists[first]
            let right = lists[second]

            // A member run lists a type's members; an enum or a name array lists values. Members
            // are compared only with members — and never two values read in one construct, as
            // `copy.a = source.a` reads `source` and writes `copy`, which is one list, not two.
            guard (left.carrier == .memberRun) == (right.carrier == .memberRun),
                  left.file != right.file || left.line != right.line else { continue }

            // Anchor on the longer list: the pair must describe a substantial enumeration,
            // but the deficient side is free to be shorter than the floor.
            guard max(left.names.count, right.names.count) >= Self.minEntries else { continue }

            let shared = left.names.intersection(right.names)
            let unionCount = left.names.count + right.names.count - shared.count
            guard unionCount > 0 else { continue }
            let similarity = Double(shared.count) / Double(unionCount)

            // `>= 1.0` means the lists agree exactly — no drift, and for enum/enum pairs
            // that is `ParallelEnumShape`'s finding, not this rule's.
            guard similarity >= Self.minSimilarity, similarity < 1.0 else { continue }

            offer(deficient: first, counterpart: second, shared: shared.count, similarity: similarity)
            offer(deficient: second, counterpart: first, shared: shared.count, similarity: similarity)
        }

        // Emit in a stable order so runs are reproducible (the pair walk is dictionary-ordered).
        for deficient in best.keys.sorted() {
            guard let match = best[deficient] else { continue }
            emit(
                deficient: lists[deficient],
                counterpart: lists[match.counterpart],
                shared: match.shared
            )
        }
    }

    /// How many member runs, at distinct places, read exactly each set of members.
    private func memberRunAgreementCounts() -> [Set<String>: Int] {
        var places: [Set<String>: Set<String>] = [:]
        for list in lists where list.carrier == .memberRun {
            places[list.names, default: []].insert("\(list.file):\(list.line)")
        }
        return places.mapValues(\.count)
    }

    /// Index-derived candidate pairs sharing at least `minShared` entries. Building
    /// candidates from an inverted index — rather than testing all pairs — is what keeps
    /// this affordable on a large project.
    private func candidatePairs() -> [(Int, Int)] {
        var index: [String: [Int]] = [:]
        for (position, list) in lists.enumerated() {
            for name in list.names {
                index[name, default: []].append(position)
            }
        }

        var sharedCounts: [Int64: Int] = [:]
        for (_, positions) in index where positions.count > 1 && positions.count <= Self.maxFanout {
            for outer in 0..<positions.count {
                for inner in (outer + 1)..<positions.count {
                    let low = min(positions[outer], positions[inner])
                    let high = max(positions[outer], positions[inner])
                    sharedCounts[Int64(low) << 32 | Int64(high), default: 0] += 1
                }
            }
        }

        return sharedCounts
            .filter { $0.value >= Self.minShared }
            .keys
            .map { (Int($0 >> 32), Int($0 & 0xFFFF_FFFF)) }
            .sorted { $0 < $1 }
    }

    /// Emits one issue at `deficient` when `counterpart` carries entries it lacks. A pair
    /// where each side has unique entries produces two issues — both need fixing; a strict
    /// subset produces one, at the list that is actually missing something.
    private func emit(deficient: NameList, counterpart: NameList, shared: Int) {
        let missing = counterpart.names.subtracting(deficient.names)
        guard !missing.isEmpty else { return }

        let missingList = counterpart.spellings(of: missing).joined(separator: ", ")
        let peer = "`\(counterpart.owner)` (\(counterpart.carrier.rawValue), "
            + "\(shortName(counterpart.file)):\(counterpart.line))"

        addIssue(
            severity: .info,
            message: "`\(deficient.owner)` (\(deficient.carrier.rawValue), "
                + "\(deficient.names.count) entries) agrees with \(peer) on \(shared) entries "
                + "but is missing \(missing.count): \(missingList).",
            filePath: deficient.file,
            lineNumber: deficient.line,
            suggestion: deficient.carrier == .memberRun
                ? Self.memberRunSuggestion(missing: missing.count)
                : "These two lists look like the same enumeration maintained in two "
                    + "places. Add the missing \(missing.count == 1 ? "entry" : "entries"), or "
                    + "derive one list from the other so they cannot drift again — if the "
                    + "counterpart is an enum, iterate `CaseIterable` instead of restating it.",
            ruleName: .parallelListDrift
        )
    }

    /// For a member run, "derive one list from the other" has a concrete form: the type names the
    /// family once, and every enumeration reads that.
    private static func memberRunSuggestion(missing: Int) -> String {
        "Both read the same family of one type's members, and this one reads fewer. If it means "
            + "the whole family, add the missing \(missing == 1 ? "member" : "members") — better, "
            + "give the type one computed property that enumerates the family and read that in "
            + "both places, so a member added later reaches every enumeration at once. If the "
            + "subset is deliberate, say why in a comment: the next reader will ask."
    }

    private func shortName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}
