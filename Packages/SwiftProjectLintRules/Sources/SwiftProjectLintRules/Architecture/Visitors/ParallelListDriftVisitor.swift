import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
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
/// **Phase 1 (walk).** Catalogs every "name list" from three carriers:
///   1. `enum` case names,
///   2. array literals whose elements are uniformly name-like (string literals,
///      leading-dot members, or type references),
///   3. runs of consecutive registration calls (`register…`/`add…`/…) from which a
///      distinguishing name can be read — the shape of `BuiltInRules.registerAll`.
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
    }

    private struct NameList {
        let owner: String                  // `PatternCategory`, `packs`, `registerFactory(…)`
        let carrier: Carrier
        let names: Set<String>             // normalized
        let display: [String: String]      // normalized → original spelling
        let file: String
        let line: Int

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
        let names = node.memberBlock.members.flatMap { member -> [String] in
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { return [] }
            return caseDecl.elements.map(\.name.text)
        }
        record(names, owner: node.name.text, carrier: .enumCases, node: Syntax(node))
        return .visitChildren
    }

    // MARK: - Phase 1: carrier 2 — array literals

    override func visit(_ node: ArrayExprSyntax) -> SyntaxVisitorContinueKind {
        // Every element must be name-like, and of one uniform kind — a mixed array is a
        // data structure, not an enumeration of names.
        var names: [String] = []
        var kinds: Set<String> = []
        for element in node.elements {
            guard let (name, kind) = nameAndKind(of: element.expression) else {
                return .visitChildren
            }
            names.append(name)
            kinds.insert(kind)
        }
        guard kinds.count == 1 else { return .visitChildren }
        record(names, owner: enclosingBindingName(of: node) ?? "array literal",
               carrier: .arrayLiteral, node: Syntax(node))
        return .visitChildren
    }

    /// The variable/property name an array literal is bound to, by walking up to the
    /// nearest `PatternBindingSyntax` — `let packs = [...]` → `packs`.
    private func enclosingBindingName(of node: ArrayExprSyntax) -> String? {
        var current: Syntax? = node.parent
        while let syntax = current {
            if let binding = syntax.as(PatternBindingSyntax.self) {
                return binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
            }
            // Stop at a declaration boundary: an array nested inside a function body
            // has no meaningful owning binding above it.
            if syntax.is(CodeBlockSyntax.self) { return nil }
            current = syntax.parent
        }
        return nil
    }

    // MARK: - Phase 1: carrier 3 — registration-call runs

    override func visit(_ node: CodeBlockItemListSyntax) -> SyntaxVisitorContinueKind {
        collectCallRuns(in: node)
        return .visitChildren
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
            guard let call = RegistrationVerb.call(in: item),
                  let name = registeredName(from: call) else {
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

    /// The distinguishing name a registration call contributes. Checks the trailing
    /// closure first — `registerFactory { _, _ in StateManagement(…) }` names its subject
    /// only in the closure body — then falls back to the first name-like argument.
    private func registeredName(from call: FunctionCallExprSyntax) -> String? {
        if let closure = call.trailingClosure,
           let last = closure.statements.last,
           case .expr(let expr) = last.item,
           let (name, _) = nameAndKind(of: expr) {
            return name
        }
        for argument in call.arguments {
            if let (name, _) = nameAndKind(of: argument.expression) { return name }
        }
        return nil
    }

    // MARK: - Name extraction

    /// Reads a name out of an expression, with a coarse kind tag used to require array
    /// elements to be uniform. Returns nil for anything that is not name-like.
    private func nameAndKind(of expr: ExprSyntax) -> (name: String, kind: String)? {
        // "state-management" — single-segment string literals only (no interpolation).
        if let literal = expr.as(StringLiteralExprSyntax.self) {
            guard literal.segments.count == 1,
                  let segment = literal.segments.first?.as(StringSegmentSyntax.self) else {
                return nil
            }
            let text = segment.content.text
            return text.isEmpty ? nil : (text, "string")
        }

        // `StateManagement(…)` / `Foo.bar(…)` — read the constructed type or callee name.
        if let call = expr.as(FunctionCallExprSyntax.self) {
            return nameAndKind(of: call.calledExpression).map { ($0.name, "reference") }
        }

        if let member = expr.as(MemberAccessExprSyntax.self) {
            // `.stateManagement` — a leading-dot case reference.
            if member.base == nil {
                return (member.declName.baseName.text, "member")
            }
            // `StateManagement.self` names the base, not the `self` member.
            if member.declName.baseName.text == "self",
               let base = member.base {
                return nameAndKind(of: base).map { ($0.name, "reference") }
            }
            // `Category.stateManagement` — qualified case reference.
            return (member.declName.baseName.text, "member")
        }

        // A bare type reference: `StateManagement`. Require an uppercase initial so
        // ordinary variable references are not mistaken for names.
        if let reference = expr.as(DeclReferenceExprSyntax.self) {
            let text = reference.baseName.text
            guard text.first?.isUppercase == true else { return nil }
            return (text, "reference")
        }

        return nil
    }

    /// Normalizes a name for comparison: case- and separator-insensitive, so
    /// `UIPatterns`, `uiPatterns` and `"ui-patterns"` all collapse to `uipatterns`.
    private static func normalize(_ raw: String) -> String {
        raw.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Adds a collected list, applying the length floor and dropping test/fixture files —
    /// a test that enumerates a deliberate subset is the rule's most common false positive.
    private func record(_ raw: [String], owner: String, carrier: Carrier, node: Syntax) {
        guard !isTestOrFixtureFile() else { return }
        var names: Set<String> = []
        var display: [String: String] = [:]
        for original in raw {
            let key = Self.normalize(original)
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
            line: getLineNumber(for: node)
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

        func offer(deficient: Int, counterpart: Int, shared: Int, similarity: Double) {
            // Only a list that is actually missing something is worth reporting.
            guard !lists[counterpart].names.subtracting(lists[deficient].names).isEmpty else {
                return
            }
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
            suggestion: "These two lists look like the same enumeration maintained in two "
                + "places. Add the missing \(missing.count == 1 ? "entry" : "entries"), or "
                + "derive one list from the other so they cannot drift again — if the "
                + "counterpart is an enum, iterate `CaseIterable` instead of restating it.",
            ruleName: .parallelListDrift
        )
    }

    private func shortName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}
