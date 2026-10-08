@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax

/// Drives one cross-file visitor over a set of in-memory files the way the engine does: every
/// file walked in path order, then `finalizeAnalysis()`.
///
/// For suites that exercise several rules against the same fixtures, where a private copy of
/// this walk per rule would be the only thing the suites had in common.
enum CrossFileVisitorTestSupport {

    /// - Parameter followingAliases: `false` hands the visitor an empty alias catalog, so a
    ///   suite can show its fixture behaves differently when composition aliases are not
    ///   expanded — i.e. that the fixture reaches the code the expansion changed.
    static func issues<Visitor: CrossFileVisitorBase & CrossFilePatternVisitorProtocol>(
        of _: Visitor.Type,
        pattern: SyntaxPattern,
        files: [String: String],
        followingAliases: Bool = true
    ) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let visitor = Visitor(fileCache: cache)
        visitor.setPattern(pattern)
        if !followingAliases {
            visitor.compositionAliases = .empty
        }

        for (name, ast) in cache.sorted(by: { $0.key < $1.key }) {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == pattern.name }
    }
}
