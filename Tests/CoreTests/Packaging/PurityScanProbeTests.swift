import SwiftSyntax
import Testing

/// The source scans in `PurityOracleEntryTests` read this repository, so a gap in one shows only on
/// the day someone writes the code it misses — and then by nothing failing. Each probe here is such
/// code, scanned the way the suite scans a file, with the verdict the scan owes it.
@Suite("The purity source scans see what they claim to")
struct PurityScanProbeTests {

    typealias Scan = PurityOracleEntryTests
    static let visitors = Scan.visitorsSources + "SwiftProjectLintVisitors/"
    static let rules = "Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/"

    // MARK: - Withholdable's state

    @Test("a subscript that reaches Withholdable's state is named")
    func subscriptReachingStateIsNamed() throws {
        let file = try #require(Scan.sources.first { $0.path == Scan.withholdable })
        let probe = Scan.scanned(file.tree.description + """

        extension Withholdable {
            subscript(reviewProbe _: Void) -> Value {
                switch state {
                case .built(let value): value
                case let .withheld(_, _, placeholder): placeholder
                }
            }
        }
        """, path: Scan.withholdable)
        #expect(Scan.stateReaders(in: probe).subtracting(Scan.stateReaders(in: file)) == ["subscript(reviewProbe:)"])
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

    @Test("an oracle created with .init is found, as an entry point and in a rule helper")
    func oracleCreatedWithInitIsFound() {
        let probe = Scan.scanned("""
        import SwiftSyntax

        extension PropertyTestCandidacy {
            public static func reviewProbeByInit(_ node: ClosureExprSyntax) -> Bool {
                PurityInferrer.init().isPure(node)
            }
            public static func reviewProbeByImplicitInit(_ node: ClosureExprSyntax) -> Bool {
                let oracle: PurityInferrer = .init()
                return oracle.isPure(node)
            }
            public static func reviewProbeGivenOne(_ oracle: PurityInferrer, _ node: ClosureExprSyntax) -> Bool {
                oracle.isPure(node)
            }
        }
        """, path: Self.visitors + "PropertyTestCandidacy+ReviewProbe.swift")
        let visitorFiles = Scan.sources.filter { $0.path.hasPrefix(Scan.visitorsSources) }
        let found = Scan.publicOracleEntryPoints(in: visitorFiles + [probe]).subtracting(Scan.oracleEntryPoints)
        #expect(found.map(\.declaration).sorted() == [
            "PropertyTestCandidacy.reviewProbeByImplicitInit", "PropertyTestCandidacy.reviewProbeByInit"
        ])

        let helper = Scan.scanned("""
        final class PureClosureCandidateVisitor: BasePatternVisitor, PackagePurityConsumer {
            static let packagePurityInputs: PackagePurityInputs = [.oracle]
        }
        enum ClosureJudge {
            static func isPure(_ node: ClosureExprSyntax) -> Bool {
                let oracle: PurityInferrer = .init()
                return oracle.isPure(node)
            }
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
        let files = [helper, caller]
        let scan = Scan.undeclaredReads(
            in: files, declared: Scan.registeredDeclarations(), entryPoints: Scan.readerEntryPoints(in: files)
        )
        #expect(scan.offenders.count == 1, "\(scan.offenders)")
        #expect(scan.offenders.first?.hasPrefix("GlobalMutableStateVisitor") == true, "\(scan.offenders)")
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

    @Test("a visitor that stores an oracle does not make its registrar a reader; a labelled helper still counts")
    func storedOracleKeysOnlyLabelledInitializers() {
        let visitor = Scan.scanned("""
        final class PureClosureCandidateVisitor: BasePatternVisitor, PackagePurityConsumer {
            static let packagePurityInputs: PackagePurityInputs = [.oracle]
            private let purityInferrer = PurityInferrer()
        }
        final class ClosureJudge {
            private let purityInferrer = PurityInferrer()
            init(strict: Bool) {}
        }
        """, path: Self.rules + "Testability/Visitors/PureClosureCandidateVisitor.swift")
        let registrar = Scan.scanned("""
        enum ReviewProbeRegistrar {
            static let visitor: BasePatternVisitor.Type = PureClosureCandidateVisitor.self
        }
        """, path: Self.rules + "Testability/PatternRegistrars/ReviewProbeRegistrar.swift")
        let caller = Scan.scanned("""
        final class GlobalMutableStateVisitor: BasePatternVisitor {
            private let judge = ClosureJudge(strict: true)
        }
        """, path: Self.rules + "CodeQuality/Visitors/GlobalMutableStateVisitor.swift")
        let files = [visitor, registrar, caller]
        let scan = Scan.undeclaredReads(
            in: files, declared: Scan.registeredDeclarations(), entryPoints: Scan.readerEntryPoints(in: files)
        )
        #expect(scan.readers == 2, "\(scan.offenders)")
        #expect(scan.offenders.count == 1, "\(scan.offenders)")
        #expect(scan.offenders.first?.hasPrefix("GlobalMutableStateVisitor") == true, "\(scan.offenders)")
    }

    // MARK: - Readers' files

    @Test("a visitor's code moved into an extension file is still that visitor's")
    func extensionFileBelongsToItsVisitor() {
        let probe = Scan.scanned("""
        extension PureFunctionCandidateVisitor {
            func impureCallee(of function: FunctionDeclSyntax) -> String? {
                knownImpurePackageFunctions.settledNames.isEmpty ? nil : function.name.text
            }
        }
        """, path: Self.rules + "Testability/Visitors/PureFunctionCandidateVisitor+Join.swift")
        let scan = Scan.undeclaredReads(
            in: [probe], declared: Scan.registeredDeclarations(), entryPoints: Scan.oracleEntryPoints
        )
        #expect(scan.readers == 1)
        #expect(scan.offenders.isEmpty, "\(scan.offenders)")
    }

    @Test("an undeclared visitor's extension in a declared visitor's file is checked against its own declaration")
    func extensionOfAnUndeclaredVisitorIsChecked() {
        let probe = Scan.scanned("""
        final class PureClosureCandidateVisitor: BasePatternVisitor, PackagePurityConsumer {
            static let packagePurityInputs: PackagePurityInputs = [.oracle]
            private let purityInferrer = PurityInferrer()
        }
        extension GlobalMutableStateVisitor {
            func reviewProbeIsPure(_ node: ClosureExprSyntax) -> Bool { PurityInferrer().isPure(node) }
        }
        """, path: Self.rules + "Testability/Visitors/PureClosureCandidateVisitor.swift")
        let scan = Scan.undeclaredReads(
            in: [probe], declared: Scan.registeredDeclarations(), entryPoints: Scan.oracleEntryPoints
        )
        #expect(scan.offenders.count == 1, "\(scan.offenders)")
        #expect(scan.offenders.first?.hasPrefix("GlobalMutableStateVisitor") == true, "\(scan.offenders)")
    }
}
