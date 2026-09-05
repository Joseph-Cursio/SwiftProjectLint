@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintModels
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// The producer half of the `role` contract with `swift-infer`.
///
/// The linter has always known which of these a closure is — `PureClosureCandidateVisitor` picks
/// its law sentence off exactly this distinction. Until the manifest grew a `role` field that
/// knowledge reached the reader as prose and reached the downstream tool not at all, so 204
/// findings on this repository arrived as an undifferentiated "extractable-kernel at line N".
///
/// One test per `CollectionOperation.Kind`, because a case added there without a `seedRole` arm is
/// the drift that matters: the finding still fires, still reads correctly to a human, and silently
/// loses its classification on the way out. `SeedRoleContractTests` in SwiftInferProperties pins
/// the other end.
@Suite("Seed role — what the linter tells swift-infer the code IS")
struct SeedRoleEmissionTests {

    private func closureRole(_ source: String) -> PBTSeedRole? {
        let visitor = PureClosureCandidateVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: "L.swift", tree: syntax))
        visitor.setFilePath("L.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.first { $0.ruleName == .pureClosureCandidate }?.role
    }

    private func kernelRole(_ source: String) -> PBTSeedRole? {
        let visitor = ExtractableTotalKernelVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: "S.swift", tree: syntax))
        visitor.setFilePath("S.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.first { $0.ruleName == .extractableTotalKernel }?.role
    }

    // MARK: - One per CollectionOperation.Kind

    @Test("a sort closure is seeded as a comparator")
    func comparatorRole() {
        #expect(closureRole("""
        func run(items: [Item]) async throws {
            let ordered = items.sorted { $0.rank * 2 < $1.rank * 2 }
            try await upload(ordered)
        }
        """) == .comparator)
    }

    @Test("a filter closure is seeded as a predicate")
    func predicateRole() {
        #expect(closureRole("""
        func run(items: [Item]) async throws {
            let kept = items.filter { $0.name.hasPrefix("a") && $0.size > 10 }
            try await upload(kept)
        }
        """) == .predicate)
    }

    @Test("a map closure is seeded as a transform")
    func transformRole() {
        // Two statements: `transform` and `reducer` are gated on the closure having real body, so a
        // one-line `map` is deliberately not a finding at all.
        #expect(closureRole("""
        func run(items: [Item]) async throws {
            let names = items.map { item in
                let trimmed = item.name.trimmingCharacters(in: .whitespaces)
                return trimmed.lowercased()
            }
            try await upload(names)
        }
        """) == .transform)
    }

    @Test("a reduce closure is seeded as a reducer")
    func reducerRole() {
        #expect(closureRole("""
        func run(items: [Item]) async throws {
            let total = items.reduce(0) { running, item in
                let weighted = item.size * 2
                return running + weighted
            }
            try await upload(total)
        }
        """) == .reducer)
    }

    // MARK: - The two kernel shapes

    @Test("a tiler is seeded as a partition")
    func partitionRole() {
        // Slicing arithmetic entails a tiling — the parts reassemble the whole. That is a law a
        // correct implementation cannot fail, which is what makes the role worth carrying.
        #expect(kernelRole("""
        func upload(of data: Data, chunkSize: Int) async throws {
            let totalChunks = (data.count + chunkSize - 1) / chunkSize
            var index = 0
            while index < totalChunks {
                _ = try await send(data.dropFirst(index * chunkSize).prefix(chunkSize))
                index += 1
            }
        }
        """) == .partition)
    }

    @Test("a path derivation is seeded as a normalizer")
    func normalizerRole() {
        #expect(kernelRole("""
        func scan(rootPath: String) throws {
            let enumerator = FileManager.default.enumerator(atPath: rootPath)
            let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            while let item = enumerator?.nextObject() as? String {
                let relativePath = item.hasPrefix(prefix) ? String(item.dropFirst(prefix.count)) : item
                let dirName = (relativePath as NSString).lastPathComponent
                if skipped.contains(dirName) { continue }
            }
        }
        """) == .normalizer)
    }

    // MARK: - Silence rather than a guess

    @Test("a progress-only kernel claims no role")
    func fractionKernelHasNoRole() {
        // Progress arithmetic is a kernel worth extracting, but "monotone and terminates at 1.0" is
        // not one of the roles this vocabulary names. Inventing one to fill the field would be
        // worse than leaving it empty — the consumer would act on a classification nobody made.
        #expect(kernelRole("""
        func collect(stream: AsyncBytes, total: Int) async throws {
            var received = 0
            for try await _ in stream {
                received += 1
                let progress = Double(received) / Double(total)
                if progress - lastReported >= 0.01 { report(progress) }
            }
        }
        """) == nil)
    }

    // MARK: - How many rules classify, and which

    /// The third classifier, and the one this suite had no coverage for.
    ///
    /// `PBTSeed.role`'s doc said *"every rule but the two candidate rules"* until 2026-08-04, when
    /// there were three — and the wording ruled the third out **by name**, since
    /// `extractableTotalKernel` is a kernel rule rather than a candidate one. A reader checking that
    /// sentence against the code would have read the classification they found there as a bug.
    private func functionRole(_ source: String) -> PBTSeedRole? {
        let visitor = PureFunctionCandidateVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: "F.swift", tree: syntax))
        visitor.setFilePath("F.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.first { $0.ruleName == .pureFunctionCandidate }?.role
    }

    @Test("a pure comparator FUNCTION is classified, not just a closure")
    func functionCandidateClassifies() {
        // The closure and kernel rules already have arms above. This is the third, and without it
        // the count in the doc rests on nothing executable.
        #expect(functionRole("""
        func isBefore(_ lhs: Int, _ rhs: Int) -> Bool {
            lhs < rhs
        }
        """) == .comparator)
    }

    // MARK: - The entailment claim this repository makes

    @Test("exactly the three entailed roles claim an entailed law")
    func entailedRolesAreTheExpectedThree() {
        // Mirrored by `SeedRoleContractTests.onlyEntailedRolesClaimATemplate` in
        // SwiftInferProperties, which checks the same three against
        // `Refutability.roleEntailedTemplates`. If this set changes, that test must change with it
        // — and if it does not, this repository is advertising a law that a correct implementation
        // can fail, which is the one failure mode the whole pipeline is built to avoid.
        let entailed = Set(PBTSeedRole.allCases.filter(\.impliesEntailedLaw).map(\.rawValue))
        #expect(entailed == ["comparator", "predicate", "partition"])
    }
}
