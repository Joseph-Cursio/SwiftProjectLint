@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// A cross-file finding must be reported at the line it occupies in *its own* file, whichever
/// file the visitor happened to walk last.
///
/// Cross-file visitors collect declarations during the walk and emit them from
/// `finalizeAnalysis()`. The line lookup used to read the converter installed on the visitor,
/// which by then belonged to whatever file came last — and the analysis engine iterates an
/// unordered dictionary, so "last" changed with the process hash seed. Two runs of the same
/// binary over the same corpus reported 12% of findings at different lines (issue #67).
///
/// Each test below walks the same two files in both orders and expects the same, correct line.
/// The two files are shaped so a wrong converter cannot accidentally agree: the declaration
/// sits on line 9 of its own file, while the other file is a single long line, so measuring
/// the declaration's byte offset against it yields line 1.
@Suite
struct CrossFileLineNumberDeterminismTests {

    /// A file whose only declaration begins on line 9.
    private static let declaringSource = """
    // padding line 1
    // padding line 2
    // padding line 3
    // padding line 4
    // padding line 5
    // padding line 6
    // padding line 7
    // padding line 8
    struct OnlyUsedHere {
        func unreferencedHelper() -> Int { 1 }
        var describedElsewhere: Int { unreferencedHelper() }
    }
    """

    /// A single-line file long enough to cover the declaring file's byte offsets, so a lookup
    /// against the wrong converter resolves to line 1 rather than landing past end-of-file.
    private static let bystanderSource =
        "struct Bystander { func stir() -> Int { 2 } } // "
            + String(repeating: "x", count: 400)

    private static let declaredLine = 9

    /// Both walk orders of the two-file corpus, so a test can assert the reported line does not
    /// depend on which file the visitor saw last.
    private static func bothWalkOrders() -> [[(name: String, ast: SourceFileSyntax)]] {
        let declaring = (name: "Declaring.swift", ast: Parser.parse(source: declaringSource))
        let bystander = (name: "Bystander.swift", ast: Parser.parse(source: bystanderSource))
        return [[declaring, bystander], [bystander, declaring]]
    }

    private static func walk(
        _ visitor: some CrossFilePatternVisitorProtocol,
        over files: [(name: String, ast: SourceFileSyntax)]
    ) {
        for file in files {
            if let base = visitor as? BasePatternVisitor {
                base.setFilePath(file.name)
                base.setSourceLocationConverter(
                    SourceLocationConverter(fileName: file.name, tree: file.ast)
                )
            }
            visitor.walk(file.ast)
        }
        visitor.finalizeAnalysis()
    }

    @Test func couldBePrivateReportsDeclaringFileLineInEitherWalkOrder() {
        for order in Self.bothWalkOrders() {
            let cache = Dictionary(uniqueKeysWithValues: order.map { ($0.name, $0.ast) })
            let visitor = CouldBePrivateVisitor(fileCache: cache)
            visitor.setPattern(CouldBePrivate().pattern)
            Self.walk(visitor, over: order)

            let issues = visitor.detectedIssues.filter { $0.ruleName == .couldBePrivate }
            let finding = issues.first { $0.message.contains("OnlyUsedHere") }
            #expect(finding?.filePath == "Declaring.swift")
            #expect(finding?.lineNumber == Self.declaredLine)
        }
    }

    @Test func couldBePrivateMemberReportsDeclaringFileLineInEitherWalkOrder() {
        for order in Self.bothWalkOrders() {
            let cache = Dictionary(uniqueKeysWithValues: order.map { ($0.name, $0.ast) })
            let visitor = CouldBePrivateMemberVisitor(fileCache: cache)
            visitor.setPattern(CouldBePrivateMember().pattern)
            Self.walk(visitor, over: order)

            let issues = visitor.detectedIssues.filter { $0.ruleName == .couldBePrivateMember }
            let finding = issues.first { $0.message.contains("unreferencedHelper") }
            #expect(finding?.filePath == "Declaring.swift")
            #expect(finding?.lineNumber == Self.declaredLine + 1)
        }
    }
}
