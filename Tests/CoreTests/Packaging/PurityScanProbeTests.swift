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

    // MARK: - Oracle entry points

    @Test("a new public entry point is found in a listed file, through a helper, and from another type")
    func newEntryPointsAreFound() {
        let probe = Scan.scanned("""
        import SwiftSyntax

        extension PropertyTestCandidacy {
            public static func reviewProbeIsPure(_ node: ClosureExprSyntax) -> Bool { PurityInferrer().isPure(node) }
            public static func reviewProbeThroughAHelper(_ function: FunctionDeclSyntax) -> Bool { helper(function) }
            private static func helper(_ function: FunctionDeclSyntax) -> Bool {
                candidate(of: function, knownEquatableTypes: []) != nil
            }
            public static func reviewProbeWithoutAnOracle() -> Int { 1 }
            static func reviewProbeInternal(_ node: ClosureExprSyntax) -> Bool { PurityInferrer().isPure(node) }
        }

        public enum ReviewProbeHelper {
            public static func check(_ node: ClosureExprSyntax) -> Bool {
                PropertyTestCandidacy.reviewProbeInternal(node)
            }
        }

        public final class ReviewProbeHolder {
            let oracle = PurityInferrer()
            public init(depth: Int) {}
        }

        public struct ReviewProbeValue {
            public func judge(_ function: FunctionDeclSyntax) -> Bool { PurityInferrer().isPure(function) }
        }
        """, path: Self.visitors + "PropertyTestCandidacy+ReviewProbe.swift")
        let visitorFiles = Scan.sources.filter { $0.path.hasPrefix(Scan.visitorsSources) }
        let found = Scan.publicOracleEntryPoints(in: visitorFiles + [probe]).subtracting(Scan.oracleEntryPoints)
        #expect(found == [
            .init(
                declaration: "PropertyTestCandidacy.reviewProbeIsPure",
                tokens: ["PropertyTestCandidacy", "reviewProbeIsPure"]
            ),
            .init(
                declaration: "PropertyTestCandidacy.reviewProbeThroughAHelper",
                tokens: ["PropertyTestCandidacy", "reviewProbeThroughAHelper"]
            ),
            .init(declaration: "ReviewProbeHelper.check", tokens: ["ReviewProbeHelper", "check"]),
            .init(declaration: "ReviewProbeHolder.init(depth:)", tokens: ["ReviewProbeHolder", "depth"]),
            // An instance member: `oracleEntryPointsAreKnown` refuses it, since no token names the call.
            .init(declaration: "ReviewProbeValue.judge", tokens: [])
        ])
    }

    @Test("a rule-package helper that creates an oracle makes its callers readers, in any file")
    func ruleHelperMakesItsCallersReaders() {
        let helper = Scan.scanned("""
        final class PureClosureCandidateVisitor: BasePatternVisitor, PackagePurityConsumer {
            static let packagePurityInputs: PackagePurityInputs = [.oracle]
        }
        enum ClosureJudge {
            static func isPure(_ node: ClosureExprSyntax) -> Bool { PurityInferrer().isPure(node) }
        }
        """, path: Self.rules + "Testability/Visitors/PureClosureCandidateVisitor.swift")
        let caller = Scan.scanned("""
        final class GlobalMutableStateVisitor: BasePatternVisitor {
            override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
                _ = ClosureJudge.isPure(node)
                return .visitChildren
            }
        }
        """, path: Self.rules + "CodeQuality/Visitors/GlobalMutableStateVisitor.swift")
        let entryPoints = Scan.readerEntryPoints(in: [helper, caller])
        let scan = Scan.undeclaredReads(
            in: [helper, caller], declared: Scan.registeredDeclarations(), entryPoints: entryPoints
        )
        #expect(scan.offenders.count == 1, "\(scan.offenders)")
        #expect(scan.offenders.first?.hasPrefix("GlobalMutableStateVisitor") == true, "\(scan.offenders)")
    }
}
