import Foundation
import SwiftParser
import SwiftSyntax

/// Runs registered pattern visitors against Swift source files and aggregates lint issues.
public final class SourcePatternDetector: SourcePatternDetectorProtocol, @unchecked Sendable {
    public let registry: PatternVisitorRegistry

    /// Type names known to conform to `Identifiable` across the project.
    /// Set by `ProjectLinter` after a pre-scan phase and passed through to visitors.
    var knownIdentifiableTypes: Set<String> = []

    /// Type names known to be declared as enums across the project.
    /// Set by `ProjectLinter` after a pre-scan phase and passed through to visitors.
    var knownEnumTypes: Set<String> = []

    /// Type names known to be declared as actors across the project.
    /// Set by `ProjectLinter` after a pre-scan phase and passed through to visitors.
    var knownActorTypes: Set<String> = []

    /// Initializes a new SwiftSyntax pattern detector.
    ///
    /// - Parameter registry: The pattern visitor registry to use. Defaults to the shared registry.
    public init(registry: PatternVisitorRegistry = .shared) {
        self.registry = registry
    }

    /// Detects patterns in a single Swift source file using SwiftSyntax analysis.
    ///
    /// - Parameters:
    ///   - sourceCode: The Swift source code to analyze.
    ///   - filePath: The file path for the source code (used for issue reporting).
    ///   - categories: Optional array of pattern categories to analyze. If nil, analyzes all categories.
    /// - Returns: An array of detected lint issues.
    public func detectPatterns(
        in sourceCode: String,
        filePath: String,
        categories: [PatternCategory]? = nil,
        parsedAST: SourceFileSyntax? = nil
    ) -> [LintIssue] {
        let patterns: [SyntaxPattern]
        if let categories = categories {
            patterns = categories.flatMap { registry.getPatterns(for: $0) }
        } else {
            patterns = registry.getAllPatterns()
        }
        let requestedRules = Set(patterns.map(\.name))
        return runVisitors(
            for: patterns,
            requestedRules: requestedRules,
            sourceCode: sourceCode,
            filePath: filePath,
            parsedAST: parsedAST
        )
    }

    /// Detects specific patterns in the given source code.
    ///
    /// - Parameters:
    ///   - sourceCode: The Swift source code to analyze.
    ///   - filePath: The file path for the source code (used for issue reporting).
    ///   - ruleIdentifiers: Array of specific rule identifiers to analyze.
    /// - Returns: An array of detected lint issues.
    func detectPatterns(
        in sourceCode: String,
        filePath: String,
        ruleIdentifiers: [RuleIdentifier],
        parsedAST: SourceFileSyntax? = nil
    ) -> [LintIssue] {
        let requestedRules = Set(ruleIdentifiers)
        let allPatterns = registry.getAllPatterns()
        let patterns = allPatterns.filter { requestedRules.contains($0.name) }
        return runVisitors(
            for: patterns,
            requestedRules: requestedRules,
            sourceCode: sourceCode,
            filePath: filePath,
            parsedAST: parsedAST
        )
    }

    // MARK: - Private

    /// Rules that produce excessive false positives in test files.
    /// Tests legitimately use magic numbers in assertions, instantiate types directly,
    /// don't need public API documentation, use print() for diagnostic output,
    /// require public access for cross-module test visibility, and co-locate mock
    /// types alongside the tests that use them.
    private static let rulesSkippedInTests: Set<RuleIdentifier> = [
        .magicNumber,
        .missingDocumentation,
        .directInstantiation,
        .taskYieldOffload,
        .printStatement,
        .publicInAppTarget,
        .multipleTypesPerFile
    ]

    /// Groups patterns by visitor type, runs each visitor once, and filters
    /// the results to only include issues matching the requested rules.
    ///
    /// Previously, each pattern created its own visitor instance — so a visitor
    /// registered for N patterns would walk the AST N times, producing N copies
    /// of every issue. This method deduplicates by visitor type.
    private func runVisitors(
        for patterns: [SyntaxPattern],
        requestedRules: Set<RuleIdentifier>,
        sourceCode: String,
        filePath: String,
        parsedAST: SourceFileSyntax?
    ) -> [LintIssue] {
        let sourceFile = parsedAST ?? Parser.parse(source: sourceCode)
        let converter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
        let isTestFile = filePath.contains("Tests")
            || filePath.contains("Test")
            || filePath.hasSuffix("Test.swift")
            || filePath.hasSuffix("Tests.swift")

        // Group patterns by visitor type so each visitor walks the AST only once.
        // Use ObjectIdentifier on the metatype as the grouping key.
        var visitorTypeToPatterns: [ObjectIdentifier: (type: BasePatternVisitor.Type, patterns: [SyntaxPattern])] = [:]
        for pattern in patterns {
            guard let visitorType = pattern.visitor as? BasePatternVisitor.Type else { continue }
            let key = ObjectIdentifier(visitorType)
            visitorTypeToPatterns[key, default: (type: visitorType, patterns: [])].patterns.append(pattern)
        }

        var allIssues: [LintIssue] = []

        for (_, entry) in visitorTypeToPatterns {
            // Initialize the visitor with the first pattern (for visitors that
            // use the pattern's template). The visitor will report issues with
            // specific ruleNames regardless of which pattern was used to init.
            let visitor = entry.type.init(pattern: entry.patterns[0])
            visitor.setSourceLocationConverter(converter)
            visitor.setFilePath(filePath)
            visitor.knownIdentifiableTypes = knownIdentifiableTypes
            visitor.knownEnumTypes = knownEnumTypes
            visitor.knownActorTypes = knownActorTypes
            visitor.walk(sourceFile)

            // Filter to only the rules that were actually requested.
            var issues = visitor.detectedIssues.filter { requestedRules.contains($0.ruleName) }

            // Suppress noisy rules in test files — these produce false positives
            // in test code (assertions use magic numbers, tests instantiate directly, etc.)
            if isTestFile {
                issues = issues.filter { !Self.rulesSkippedInTests.contains($0.ruleName) }
            }

            allIssues.append(contentsOf: issues)
        }

        return allIssues
    }
}
