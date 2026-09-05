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

    /// Type names known to be `@Observable`/`ObservableObject` across the project.
    var knownObservableTypes: Set<String> { get set }

    /// Type names known to be declared as protocols across the project.
    /// `View` names reading `@Environment(SomeType.self)`; `nil` when no pre-scan ran.
    var knownObservableEnvironmentViews: Set<String>? { get set }

    var knownSPIMembers: Set<String> { get set }

    var knownFunctionTypeAliases: Set<String> { get set }

    var knownProtocolTypes: Set<String> { get set }

    /// Type names known to be `Equatable` across the project (Equatable /
    /// Hashable / Comparable, declared inline or via an extension).
    var knownEquatableTypes: Set<String> { get set }

    /// Type names declared as `struct` or `enum` (value types) across the project.
    var knownValueTypes: Set<String> { get set }

    /// Per type, sibling methods cleared as functions of their inputs by the pre-scan.
    /// Package function names the purity oracle refutes with an establishable witness —
    /// the one-hop callee join, resolved once in the pre-scan. See
    /// `PackagePurityJoin` and `BasePatternVisitor.knownImpurePackageFunctions`.
    var knownImpurePackageFunctions: Set<String> { get set }

    var knownCleanInstanceMethods: CleanInstanceMethodCatalog { get set }

    /// Functions this project declares (bare and labelled names). Lets the Pure Closure rule tell a
    /// closure that still hides logic from one merely forwarding to a function already extracted.
    var knownProjectFunctions: Set<String> { get set }

    /// Types whose initialiser has defaulted parameters — the gate for `lossyStructRebuild`.
    var knownDefaultedInitializerTypes: Set<String> { get set }

    /// Architectural layer policies for the Architectural Boundary rule.
    var layerPolicies: [LayerPolicy] { get set }

    /// Per-framework allowlist opt-in for the idempotency heuristic
    /// (round-14). `nil` = all frameworks active subject to import gating.
    var enabledFrameworkAllowlists: Set<String>? { get set }

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
