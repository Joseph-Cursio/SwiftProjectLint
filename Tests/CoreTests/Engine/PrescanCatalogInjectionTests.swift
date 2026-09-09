import Foundation
import Testing

/// Every catalog the pre-scan builds has to reach the visitors that read it.
///
/// `ProjectLinter` builds a detector, primes it with every pre-scan catalog, and then reads **one
/// field** off it:
///
/// ```swift
/// let registry = Self.configuredDetector(detector, collected: …, configuration: …).registry
/// ```
///
/// Every `resolved.knownX = …` in `configuredDetector` goes with the detector. The per-file path
/// builds a *fresh* `SourcePatternDetector` inside `analyzeFile` and primes it from
/// `FileAnalysisEnvironment`, so a catalog set only in `configuredDetector` is set nowhere that
/// matters.
///
/// Two were, and nothing noticed. `knownCleanInstanceMethods` — the per-type catalog of sibling
/// methods that are themselves functions of their inputs, whose own header explains that it exists
/// *because* a type's methods are spread across files and "is built once in the project pre-scan
/// and injected" — was built and never injected. `PureFunctionCandidateVisitor` read it and always
/// got `.empty`. Measured over four repositories when it was wired through: **+93 candidates, 0
/// lost.** `enabledFrameworkAllowlists` was the same shape and inert only because `nil` (the
/// visitor's default) happens to mean the same as the config's default; setting the option would
/// have been silently ignored for every per-file rule.
///
/// **No assertion about a rule's output would have caught either.** The linter reports fewer
/// candidates, correctly formatted, with no error anywhere — the failure is a catalog that is built
/// and then dropped, which looks exactly like a corpus that has fewer candidates in it.
///
/// So this test is structural, in the same spirit as
/// `UpwardInferenceFileOrderTests.testNoVisitorReadsFileCacheValues`: it reads the two functions'
/// source and asserts that what one primes, the other primes too. A per-catalog behavioural test
/// would pin the two instances; this pins the shape.
@Suite("Every pre-scan catalog reaches the per-file detector")
struct PrescanCatalogInjectionTests {

    @Test("what configuredDetector primes, analyzeFile primes too")
    func everyCatalogIsInjectedPerFile() throws {
        let primedOnce = try assignedFields(
            in: "Packages/SwiftProjectLintEngine/Sources/SwiftProjectLintEngine/ProjectLinter.swift",
            after: "var resolved = detector ?? SourcePatternDetector()",
            receiver: "resolved."
        )
        let primedPerFile = try assignedFields(
            in: "Packages/SwiftProjectLintEngine/Sources/SwiftProjectLintEngine/"
                + "ProjectLinter+FileAnalysis.swift",
            after: "let det = SourcePatternDetector(registry: registry)",
            receiver: "det."
        )

        // A guard on the reader rather than on the code: if either function is renamed or
        // restructured this test would otherwise pass by finding nothing.
        #expect(
            primedOnce.count >= 15,
            Comment(rawValue: "found \(primedOnce.count) fields — has configuredDetector moved?")
        )
        #expect(
            primedPerFile.count >= 15,
            Comment(rawValue: "found \(primedPerFile.count) fields — has analyzeFile moved?")
        )

        let dropped = primedOnce.subtracting(primedPerFile)
        let explanation = "primed in configuredDetector and dropped before any visitor sees it: "
            + "\(dropped.sorted()). Add each to FileAnalysisEnvironment, thread it through both "
            + "analyzeFile overloads, and assign it beside the others."
        #expect(dropped.isEmpty, Comment(rawValue: explanation))
    }

    /// The run of assignments made on `receiver` immediately after `anchor`.
    ///
    /// Anchored on the line that creates the detector rather than on the enclosing `func`, because
    /// `analyzeFile` is overloaded and the convenience wrapper assigns nothing — matching the
    /// declaration by name found the wrong one and read back an empty set, which is a test that
    /// passes by looking in the wrong place.
    private func assignedFields(
        in relativePath: String, after anchor: String, receiver: String
    ) throws -> Set<String> {
        let url = Self.repositoryRoot.appendingPathComponent(relativePath)
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        let start = try #require(
            lines.firstIndex { $0.contains(anchor) },
            Comment(rawValue: "anchor not found in \(relativePath): \(anchor)")
        )

        var fields: Set<String> = []
        for line in lines[(start + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") { continue }
            guard trimmed.hasPrefix(receiver), let equals = trimmed.firstIndex(of: "=") else {
                // The assignments are one contiguous run in both functions. The first line that is
                // not one of them ends it, so a later `det.` write elsewhere cannot creep in.
                break
            }
            let name = trimmed[trimmed.index(trimmed.startIndex, offsetBy: receiver.count)..<equals]
            fields.insert(name.trimmingCharacters(in: .whitespaces))
        }
        return fields
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Engine
            .deletingLastPathComponent()   // CoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
    }
}
