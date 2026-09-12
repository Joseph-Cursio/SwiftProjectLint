import Foundation
import SwiftParser
import SwiftSyntax
import Testing

/// **Every walk inside a `finalizeAnalysis` has a stated order.**
///
/// This is the law `DetectorRobustnessPropertyTests.detection_isDeterministic` claimed and could
/// not reach (SwiftProjectLint#203). That one calls `detectPatterns(in:filePath:)`, which never
/// invokes `finalizeAnalysis`, and it compares two calls **in one process** — where Swift's hash
/// seed is fixed, so a rule whose output depends on the seed is perfectly self-consistent within a
/// run and differs between runs. Calling the detector twice cannot vary the thing that varies.
///
/// ## Why this is a source check rather than a run
///
/// The two runtime shapes the issue proposed both fail for the same reason: the variable is the
/// per-process hash seed, and no assertion made inside one process can move it. Shuffling the file
/// order reaches insertion-order dependence and not this; spawning the binary twice reaches it only
/// when the corpus happens to contain a colliding pair, and even then it is a coin flip per run —
/// #202's own kill rates were 5/10 and 6/10 for exactly that reason. A test whose subject is a hash
/// seed cannot be a decision on one run. A test about the *source* can.
///
/// ## What the survey found, which is why the rule is blanket rather than targeted
///
/// All 29 cross-file visitors were read. One had a live defect —
/// `PrimitiveNamedForDomainType` resolved a case-insensitive collision last-write-wins from a
/// `Dictionary` walk, naming `UserId` in 8 of 12 processes and `UserID` in the other 4. Five had
/// already handled the hazard by hand, each with its own comment: `CircularDependency` (#202),
/// `ParallelListDrift`, `PrimitiveBypassingDomainType`, `HoistableConformerMember`,
/// `MissingEquatableOnStateType`. The rest were safe, but safe *by argument* — each one needed a
/// reader to establish that its unordered walk could not leak.
///
/// One author in six got that argument wrong. This check removes the argument: the walk has an
/// order, so nothing downstream of it has to be reasoned about. The cost is nil — these maps hold
/// tens of entries — and the shape it forecloses is real and recurring: state carried across the
/// loop, like `CircularDependency`'s `reported` set, makes the *first* iteration decide which of
/// two equally-valid findings is suppressed.
///
/// ## What it does not claim
///
/// It reads the sequence expression of each `for`-in and nothing else. A `Dictionary` reached
/// through a local alias, through a function call, or through `Dictionary(grouping:)` assigned to a
/// `let` is outside it — so this narrows the surface rather than closing it, and the doc comments
/// on the five hand-handled visitors are still the record for why their *selections* are stable.
@Suite("Cross-file aggregation walks are ordered")
struct AggregationDeterminismTests {

    // MARK: - Fixtures

    private static var packagesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CrossFileAnalysis
            .deletingLastPathComponent()   // CoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("Packages")
    }

    /// Every Swift file under `Packages/` that declares a `finalizeAnalysis`, excluding the
    /// checkouts SwiftPM drops inside those package directories.
    private static func aggregatingSources() throws -> [(url: URL, text: String)] {
        let enumerator = FileManager.default.enumerator(
            at: packagesDirectory, includingPropertiesForKeys: nil
        )
        var found: [(URL, String)] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            guard url.path.contains("/.build/") == false else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            guard text.contains("func finalizeAnalysis") else { continue }
            found.append((url, text))
        }
        return found.sorted { $0.0.path < $1.0.path }
    }

    // MARK: - The law

    @Test("no finalizeAnalysis walks a Dictionary or Set without ordering it")
    func aggregationWalksAreOrdered() throws {
        let sources = try Self.aggregatingSources()
        // A guard on the guard: a path typo would make every assertion below pass on nothing.
        #expect(sources.count >= 25)

        var offenders: [String] = []
        for (url, text) in sources {
            let tree = Parser.parse(source: text)
            let finder = UnorderedWalkFinder(unordered: UnorderedNames.declared(in: tree))
            finder.walk(tree)
            for walk in finder.unorderedWalks {
                offenders.append("\(url.lastPathComponent): for … in \(walk)")
            }
        }

        #expect(offenders.isEmpty, "\(offenders.joined(separator: "\n"))")
    }
}

// MARK: - Syntax

/// The names declared as a `Dictionary` or `Set` anywhere in a file.
///
/// File-wide rather than scope-aware, and deliberately so: a visitor's aggregation state is a
/// stored property of the type, and the locals a `finalizeAnalysis` builds are named distinctly
/// from it. Over-collecting costs a `.sorted()` nobody needed; under-collecting costs the finding.
private enum UnorderedNames {

    static func declared(in tree: SourceFileSyntax) -> Set<String> {
        let collector = Collector(viewMode: .sourceAccurate)
        collector.walk(tree)
        return collector.names
    }

    private final class Collector: SyntaxVisitor {
        var names: Set<String> = []

        override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
            guard let name = node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
            else { return .visitChildren }
            if let annotation = node.typeAnnotation?.type, Self.isUnordered(annotation) {
                names.insert(name)
            }
            return .visitChildren
        }

        /// `[K: V]` and `Set<E>`, in either spelling. An array literal type is ordered and a
        /// `Dictionary`'s *values* are not, which is why `[V]` is absent here.
        private static func isUnordered(_ type: TypeSyntax) -> Bool {
            if type.is(DictionaryTypeSyntax.self) { return true }
            if let identifier = type.as(IdentifierTypeSyntax.self) {
                return identifier.name.text == "Set" || identifier.name.text == "Dictionary"
            }
            return false
        }
    }
}

/// The `for`-in sequences inside a `finalizeAnalysis` that are rooted at an unordered name and do
/// not go through `sorted`.
private final class UnorderedWalkFinder: SyntaxVisitor {
    private let unordered: Set<String>
    private var depth = 0
    var unorderedWalks: [String] = []

    init(unordered: Set<String>) {
        self.unordered = unordered
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.name.text == "finalizeAnalysis" { depth += 1 }
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        if node.name.text == "finalizeAnalysis" { depth -= 1 }
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        guard depth > 0 else { return .visitChildren }
        let sequence = node.sequence
        let text = sequence.trimmedDescription
        if let root = Self.rootName(of: sequence), unordered.contains(root),
           text.contains("sorted") == false {
            unorderedWalks.append(text)
        }
        return .visitChildren
    }

    /// The bare identifier a member chain is rooted at — `groups` for `groups.values`.
    ///
    /// A call stops the walk: `candidatePairs()` is a function, and what it returns is its own
    /// business (`ParallelListDrift`'s sorts before returning). Subscripts stop it too, because
    /// `typeReferences[typeA] ?? []` yields the *value*, which is an array.
    private static func rootName(of expression: ExprSyntax) -> String? {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        if let member = expression.as(MemberAccessExprSyntax.self) {
            return member.base.flatMap(rootName(of:))
        }
        return nil
    }
}
