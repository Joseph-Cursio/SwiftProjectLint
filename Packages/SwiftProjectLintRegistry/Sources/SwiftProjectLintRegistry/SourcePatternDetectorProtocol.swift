//
//  SourcePatternDetectorProtocol.swift
//  SwiftProjectLint
//
//  Created by joe cursio on 7/14/25.
//
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Protocol for pattern detection operations.
///
/// Defines the full contract for detecting lint patterns in Swift source code,
/// including both category-based and rule-based filtering, plus cross-file type
/// metadata used to suppress false positives.
public protocol SourcePatternDetectorProtocol {
    /// The underlying registry used for pattern lookup.
    var registry: PatternVisitorRegistry { get }

    /// Type names known to conform to `Identifiable` across the project.
    var knownIdentifiableTypes: Set<String> { get set }

    /// Type names known to be declared as enums across the project.
    var knownEnumTypes: Set<String> { get set }

    /// Type names known to be declared as actors across the project.
    var knownActorTypes: Set<String> { get set }

    /// All type names (class, struct, enum, actor) declared anywhere in the project.
    var knownLocalTypeNames: Set<String> { get set }

    /// Architectural layer policies for the Architectural Boundary rule.
    var layerPolicies: [LayerPolicy] { get set }

    /// Per-framework whitelist opt-in for the idempotency heuristic
    /// (round-14). `nil` = all frameworks active subject to import gating.
    var enabledFrameworkWhitelists: Set<String>? { get set }

    /// Detects patterns filtered by category.
    func detectPatterns(
        in sourceCode: String,
        filePath: String,
        categories: [PatternCategory]?,
        parsedAST: SourceFileSyntax?
    ) -> [LintIssue]

    /// Detects patterns filtered by specific rule identifiers.
    func detectPatterns(
        in sourceCode: String,
        filePath: String,
        ruleIdentifiers: [RuleIdentifier],
        parsedAST: SourceFileSyntax?
    ) -> [LintIssue]
}
