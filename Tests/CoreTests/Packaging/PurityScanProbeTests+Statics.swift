import Foundation
import Testing

/// The static scan's probes: what `noStaticHoldsAnOracle` must find, and the one exception it makes.
extension PurityScanProbeTests {

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

    @Test("a sanctioned name is no exception when its constant is built from a run")
    func sanctionedConstantIsBuiltFromNothing() {
        let builtFromARun = [
            "Self(inferrer: PurityInferrer())",
            "Self.build(from: [])",
            "CleanInstanceMethodCatalog(methodsByType: PackagePurity.current.cleanMethods)"
        ]
        for value in builtFromARun {
            let probe = Scan.scanned("""
            public struct CleanInstanceMethodCatalog {
                public static let empty = \(value)
            }
            """, path: Self.visitors + "CleanInstanceMethodCatalog.swift")
            #expect(
                Scan.staticOffenders(in: [probe]) == [Self.visitors + "CleanInstanceMethodCatalog.swift: empty"],
                "\(value)"
            )
        }
        let purity = Scan.scanned("""
        public struct PackagePurity {
            public static let unconfigured = Self(universe: [], constructionFacts: .empty)
            @TaskLocal public static var current: PackagePurity = .unconfigured
        }
        """, path: Scan.packagePurity)
        #expect(Scan.staticOffenders(in: [purity]).isEmpty)
    }

    @Test("a static holding the detector or a visitor is an offender; a visitor's metatype is not")
    func staticDetectorsAndVisitorsAreOffenders() {
        let probe = Scan.scanned("""
        final class ReviewProbeVisitor: BasePatternVisitor {}
        final class ReviewProbeSubVisitor: ReviewProbeVisitor, PackagePurityConsumer {}
        enum ReviewProbeDetectorCache {
            nonisolated(unsafe) static var lastDetector: SourcePatternDetector?
            nonisolated(unsafe) static var lastVisitor: ReviewProbeSubVisitor?
            nonisolated(unsafe) static var lastBase = BasePatternVisitor(patternCategory: .codeQuality)
            static let visitorType: BasePatternVisitor.Type = ReviewProbeSubVisitor.self
            static let visitorTypes = [ReviewProbeVisitor.self]
        }
        """, path: "Packages/SwiftProjectLintRegistry/Sources/SwiftProjectLintRegistry/SourcePatternDetector.swift")
        let names = Scan.staticOffenders(in: [probe]).map { $0.components(separatedBy: ": ").last ?? $0 }
        #expect(names.sorted() == ["lastBase", "lastDetector", "lastVisitor"])
    }

    @Test("a type that can be withheld is held the day it is added, without editing the list")
    func newSurfaceIsHeld() {
        let surface = Scan.scanned("""
        public struct ReviewProbeSurface: Sendable {
            private let storage: Withholdable<Int>
            static func withheld(by tripwire: PurityTripwire) -> Self {
                Self(storage: .withheld(.oracle, by: tripwire, answering: 0))
            }
        }
        """, path: Self.visitors + "ReviewProbeSurface.swift")
        let cache = Scan.scanned("""
        enum ReviewProbeSurfaceCache {
            nonisolated(unsafe) static var last: ReviewProbeSurface?
        }
        """, path: Self.rules + "ReviewProbeSurfaceCache.swift")
        #expect(Scan.heldByOneRun(in: [surface]).contains("ReviewProbeSurface"))
        #expect(Scan.staticOffenders(in: [surface, cache]) == [Self.rules + "ReviewProbeSurfaceCache.swift: last"])
    }
}
