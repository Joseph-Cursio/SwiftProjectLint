import SwiftProjectLintModels
import SwiftProjectLintVisitors

extension ParallelListDriftVisitor {
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
        PathString.lastComponent(of: path)
    }
}
