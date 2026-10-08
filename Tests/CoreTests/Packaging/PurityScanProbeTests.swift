import Foundation
import SwiftSyntax
import Testing

/// The source scans in `PurityOracleEntryTests` read this repository, so a gap in one shows only on
/// the day someone writes the code it misses — and then by nothing failing. Each probe here is such
/// code, scanned the way the suite scans a file, with the verdict the scan owes it.
@Suite("The purity source scans see what they claim to")
struct PurityScanProbeTests {

    private typealias Scan = PurityOracleEntryTests
    private static let visitors = Scan.visitorsSources + "SwiftProjectLintVisitors/"
    private static let rules = "Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/"

    // MARK: - Statics

    @Test("a static holding a purity catalog or the join is an offender, Self included")
    func staticCatalogsAreOffenders() {
        let probe = Scan.scanned("""
        enum ReviewProbeCatalogCache {
            nonisolated(unsafe) static var lastClean: CleanInstanceMethodCatalog = .empty
            nonisolated(unsafe) static var lastJoin = ImpurePackageFunctions.empty
            nonisolated(unsafe) static var lastJoinValue: PackagePurityJoin?
            static let lastCollected: [CollectedTypes] = []
            static let names: Set<String> = []
        }
        extension CleanInstanceMethodCatalog {
            nonisolated(unsafe) static var cached = Self.empty
        }
        """, path: "Packages/SwiftProjectLintRegistry/Sources/SwiftProjectLintRegistry/SourcePatternDetector.swift")
        let names = Scan.staticOffenders(in: [probe]).map { $0.components(separatedBy: ": ").last ?? $0 }
        #expect(names.sorted() == ["cached", "lastClean", "lastCollected", "lastJoin", "lastJoinValue"])
    }

    @Test("only the sanctioned empty constant passes, and only as a let")
    func sanctionedConstantIsALet() {
        let probe = Scan.scanned("""
        public struct CleanInstanceMethodCatalog {
            public static let empty = Self(methodsByType: [:])
            nonisolated(unsafe) static var lastRun = Self.empty
        }
        """, path: Self.visitors + "CleanInstanceMethodCatalog.swift")
        #expect(Scan.staticOffenders(in: [probe]) == [Self.visitors + "CleanInstanceMethodCatalog.swift: lastRun"])

        let mutable = Scan.scanned("""
        public struct CleanInstanceMethodCatalog {
            nonisolated(unsafe) public static var empty = Self(methodsByType: [:])
        }
        """, path: Self.visitors + "CleanInstanceMethodCatalog.swift")
        #expect(Scan.staticOffenders(in: [mutable]) == [Self.visitors + "CleanInstanceMethodCatalog.swift: empty"])
    }
}
