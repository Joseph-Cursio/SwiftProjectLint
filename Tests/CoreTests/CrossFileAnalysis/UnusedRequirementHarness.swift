@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Runs `UnusedProtocolRequirementVisitor` over in-memory files and returns the requirements it
/// reports, as `Protocol.requirement(labels:)`. Shared by the rule's test suites.
enum UnusedRequirementHarness {

    static func issues(_ files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let visitor = UnusedProtocolRequirementVisitor(fileCache: cache)
        visitor.setPattern(UnusedProtocolRequirement().pattern)
        for (name, tree) in cache.sorted(by: { $0.key < $1.key }) {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: tree))
            visitor.walk(tree)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .unusedProtocolRequirement }
    }

    /// `["OrderStore.recentOrders()"]` — sorted, so a test can compare with `==`.
    static func reported(_ files: [String: String]) -> [String] {
        issues(files).compactMap(requirementName).sorted()
    }

    private static func requirementName(_ issue: LintIssue) -> String? {
        let parts = issue.message.components(separatedBy: "'")
        guard parts.count >= 4 else { return nil }
        return "\(parts[3]).\(parts[1])"
    }
}
