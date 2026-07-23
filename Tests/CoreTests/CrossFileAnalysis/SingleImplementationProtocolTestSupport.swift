@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// The shared driver for the `SingleImplementationProtocol` suites.
///
/// The rule's tests outgrew one file, and the two halves both need this exact walk. Keeping
/// one copy here means a change to how the visitor is driven cannot land in one suite and
/// miss the other.
enum SingleImplementationProtocolTestSupport {

    static func analyze(
        files: [String: String],
        executablePaths: [String] = []
    ) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = SingleImplementationProtocol().pattern
        let visitor = SingleImplementationProtocolVisitor(fileCache: cache)
        visitor.setPattern(pattern)
        visitor.executableSourcePaths = executablePaths

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .singleImplementationProtocol }
    }
}
