import Foundation
import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Body-effect inference must see the project's files in a fixed order.
///
/// The four idempotency visitors that run upward inference each passed
/// `Array(fileCache.values)` into `applyBodyInference`. That is a dictionary's values, so the
/// order came from the process hash seed and changed on every launch — and the fixed-point walk
/// reached a non-idempotent leaf by a different route each time.
///
/// **Measured**, against `SwiftInferProperties` with the CLI: the same violation was reported as
/// resting on a "5-hop chain of un-annotated callees" on one run and a "4-hop chain" on the next.
/// One line of 1,523 differed. The finding was correct both times and pointed at the same call;
/// only the number a reader would use to judge how much to trust it moved.
///
/// **Why the assertions below are about ordering rather than about hop counts.** The hash seed is
/// fixed for the lifetime of a process, so two analyses inside one test run see the *same*
/// dictionary order — a test that analysed a fixture twice and compared would have passed against
/// the broken code. The bug is only observable across processes. What a test can pin is the input
/// order the inference is handed, which is the thing that was wrong; the cross-process behaviour
/// was verified by running the built CLI five times over a real corpus.
@Suite("Idempotency — upward inference sees files in a fixed order")
struct UpwardInferenceFileOrderTests {

    /// Deliberately not in sorted order, and not in an order a hash is likely to reproduce.
    private static let sources: [String: String] = [
        "Zebra.swift": "func zebra() {}",
        "Alpha.swift": "func alpha() {}",
        "Middle.swift": "func middle() {}",
        "Beta.swift": "func beta() {}"
    ]

    private static func fileCache() -> [String: SourceFileSyntax] {
        sources.mapValues { Parser.parse(source: $0) }
    }

    @Test("orderedSources walks the cache by path")
    func testOrderedSourcesIsSortedByPath() {
        let cache = Self.fileCache()
        let visitor = IdempotencyViolationVisitor(fileCache: cache)

        let walked = visitor.orderedSources.map(\.description)
        let expected = cache.keys.sorted().compactMap { cache[$0]?.description }

        #expect(walked == expected)
        #expect(walked.count == Self.sources.count)
    }

    /// All four upward-inference visitors inherit the same accessor, so one check covers them —
    /// but only while they keep using it. This is the reason for `testNoVisitorReadsFileCacheValues`.
    @Test("every upward-inference visitor orders its sources the same way")
    func testAllUpwardInferenceVisitorsAgree() {
        let cache = Self.fileCache()
        let expected = cache.keys.sorted()

        let orders: [[String]] = [
            IdempotencyViolationVisitor(fileCache: cache).orderedSources,
            OnceContractViolationVisitor(fileCache: cache).orderedSources,
            NonIdempotentInRetryContextVisitor(fileCache: cache).orderedSources,
            UnannotatedInStrictReplayableContextVisitor(fileCache: cache).orderedSources
        ].map { sources in
            sources.compactMap { source in
                cache.first { $0.value.description == source.description }?.key
            }
        }

        for order in orders {
            #expect(order == expected)
        }
    }

    /// The fix is one line per visitor, and reintroducing the bug is one line too.
    ///
    /// `fileCache.values` reads as harmless — it is only wrong because the *order* of a
    /// dictionary's values is not a property of its contents, which is invisible at the call site
    /// and produces no warning. A grep is the only thing that catches the next one; this test is
    /// that grep, run.
    @Test("no visitor reads fileCache.values directly")
    func testNoVisitorReadsFileCacheValues() throws {
        let packages = Self.repositoryRoot.appendingPathComponent("Packages")
        let enumerator = try #require(
            FileManager.default.enumerator(at: packages, includingPropertiesForKeys: nil)
        )

        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            guard text.contains("fileCache.values") else { continue }
            // The base class is where the ordered accessor is defined; it is allowed to look.
            guard url.lastPathComponent != "CrossFileVisitorBase.swift" else { continue }
            offenders.append(url.lastPathComponent)
        }

        #expect(offenders.isEmpty, "use `orderedSources` instead: \(offenders.sorted())")
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Idempotency
            .deletingLastPathComponent()   // CoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
    }
}
