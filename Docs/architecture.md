# SwiftProjectLint Architecture

This document describes how the codebase is organized and how its major components fit together.

---

## Package Structure

The project is a Swift Package with three executable/library targets and six local packages:

```
SwiftProjectLint/
├── Sources/
│   ├── Core/      — thin facade that re-exports all local packages
│   ├── App/       — macOS SwiftUI application
│   └── CLI/       — command-line tool
│
└── Packages/
    ├── SwiftProjectLintModels/     — value types (no dependencies)
    ├── SwiftProjectLintVisitors/   — base visitor infrastructure
    ├── SwiftProjectLintRegistry/   — pattern registry and detection engine
    ├── SwiftProjectLintConfig/     — YAML config, file discovery, suppression
    ├── SwiftProjectLintRules/      — all lint rule implementations
    └── SwiftProjectLintEngine/     — orchestration and cross-file analysis
```

`Core` contains a single `Exports.swift` that uses `@_exported import` to re-export all six local packages, so `App` and `CLI` only need to `import Core`.

External dependencies: SwiftSyntax/SwiftParser (602.0.0), Yams, Swift Argument Parser, ViewInspector (test only).

### Dependency Graph

```
SwiftProjectLintModels          (no dependencies)
        ↑
SwiftProjectLintVisitors        (+ SwiftSyntax)
        ↑
SwiftProjectLintRegistry        (+ SwiftSyntax)
    ↑           ↑
SwiftProjectLintConfig      SwiftProjectLintRules
    (+ Yams)                    (+ SwiftSyntax)
        ↑           ↑
SwiftProjectLintEngine
        ↑
       Core  ←—  App / CLI
```

---

## Analysis Pipeline

When `ProjectLinter.analyzeProject(at:)` is called, the following stages run in order:

```
1. FileAnalysisUtils        — discover .swift files, skip excluded paths and generated files
2. Pre-scans                — collect cross-file type metadata (Identifiable, enum, actor types, all local type names)
3. Per-file analysis        — concurrent task group, one task per file:
       Parser.parse()             parse source into SourceFileSyntax (AST)
       SourcePatternDetector      run visitors against the AST
       InlineSuppressionFilter    remove issues suppressed by comments
4. CrossFileAnalysisEngine  — detect issues that span multiple files
5. LintConfiguration        — apply per-rule severity overrides and path exclusions
```

Steps 1-3 happen in `ProjectLinter.swift` (SwiftProjectLintEngine). Steps 4-5 happen after the task group collects all per-file results.

---

## Local Packages

### SwiftProjectLintModels

Pure value types with no external dependencies. Everything else depends on this package.

```
SwiftProjectLintModels/Sources/
├── IssueSeverity.swift
├── LintIssue.swift
├── PatternCategory.swift
├── ProjectFile.swift
├── RuleIdentifier.swift
├── SwiftUIProtocol.swift
└── SwiftUIViewType.swift
```

### SwiftProjectLintVisitors

Base visitor infrastructure built on SwiftSyntax. Provides the `BasePatternVisitor` superclass and helper utilities used by all rule visitors.

```
SwiftProjectLintVisitors/Sources/
├── BasePatternVisitor.swift        — base class with issue-reporting utilities
├── PatternVisitor.swift            — protocol definition
├── CrossFilePatternVisitor.swift   — protocol for multi-file visitors
├── SyntaxPattern.swift             — value type linking a rule to its visitor
├── SyntaxHelpers.swift             — shared AST traversal utilities
├── ActorTypeCollector.swift        ─┐
├── EnumTypeCollector.swift          │ type collectors for pre-scan phase
├── IdentifiableTypeCollector.swift  │
├── LocalTypeCollector.swift         │ (collects all local class/struct/enum/actor names)
└── TypeCollectorProtocol.swift     ─┘
```

### SwiftProjectLintRegistry

Decouples visitor classes from the detection engine:

```
SwiftProjectLintRegistry/Sources/
├── SourcePatternRegistry.swift         — holds all registered SyntaxPattern values
├── SourcePatternRegistryProtocol.swift
├── PatternVisitorRegistry.swift        — maps SyntaxPattern → visitor type
├── PatternVisitorRegistryProtocol.swift
├── SourcePatternDetector.swift         — creates visitor instances and drives the walk
├── SourcePatternDetectorProtocol.swift
├── PatternRegistrationProtocol.swift   — PatternRegistrarProtocol, BasePatternRegistrar
└── DetectionPattern.swift
```

### SwiftProjectLintConfig

Configuration loading, file discovery, and inline suppression. Depends on Yams for YAML parsing.

```
SwiftProjectLintConfig/Sources/
├── Configuration/
│   ├── LintConfiguration.swift
│   ├── LintConfigurationLoader.swift
│   ├── LintConfigurationWriter.swift
│   ├── ConfigurationPersistenceProtocol.swift
│   └── ExecutableTargetDetector.swift
├── FileAnalysis/
│   ├── FileAnalysisUtils.swift
│   ├── FileDiscoveryProtocol.swift
│   ├── DirectoryScanner.swift
│   └── DirectoryNode.swift
└── Suppression/
    ├── InlineSuppressionParser.swift
    └── InlineSuppressionFilter.swift
```

### SwiftProjectLintRules

All lint rule implementations, organized by category. Each category has a `Visitors/` folder and a `PatternRegistrars/` folder. `BuiltInRuleRegistration.swift` at the root wires all category registrars together.

```
SwiftProjectLintRules/Sources/
├── BuiltInRuleRegistration.swift
├── Accessibility/
│   ├── Visitors/
│   └── PatternRegistrars/
├── Animation/
│   ├── Visitors/
│   └── PatternRegistrars/
├── Architecture/
│   ├── Visitors/
│   └── PatternRegistrars/
├── CodeQuality/
│   ├── Visitors/
│   └── PatternRegistrars/
├── MemoryManagement/
│   ├── Visitors/
│   └── PatternRegistrars/
├── Modernization/
│   ├── Visitors/
│   └── PatternRegistrars/
├── Networking/
│   ├── Visitors/
│   └── PatternRegistrars/
├── Performance/
│   ├── Visitors/
│   └── PatternRegistrars/
├── Security/
│   ├── Visitors/
│   └── PatternRegistrars/
├── StateManagement/
│   ├── Visitors/
│   └── PatternRegistrars/
└── UI/
    ├── Visitors/
    └── PatternRegistrars/
```

### SwiftProjectLintEngine

Top-level orchestration. Depends on all other local packages.

```
SwiftProjectLintEngine/Sources/
├── ProjectLinter.swift             — top-level analysis orchestrator
├── PatternRegistryFactory.swift    — factory for creating configured systems
├── ProjectAnalyzerProtocol.swift
└── CrossFileAnalysis/
    ├── CrossFileAnalysisEngine.swift
    └── CrossFileAnalyzerProtocol.swift
```

---

## Visitor Pattern

Every lint rule is implemented as a SwiftSyntax visitor. All visitors inherit from `BasePatternVisitor`, which extends SwiftSyntax's `SyntaxVisitor`:

```
SyntaxVisitor  (SwiftSyntax)
    └── BasePatternVisitor      — common issue-reporting utilities
            └── ForceTryVisitor
            └── MagicNumberVisitor
            └── AccessibilityVisitor
            └── ...
```

A visitor overrides `visit(_:)` or `visitPost(_:)` for the specific syntax node types it cares about. When it detects a violation it calls `addIssue(...)`, which records a `LintIssue`.

---

## Pattern Registry

Registration happens at startup via `PatternRegistryFactory.createConfiguredSystem()`, which calls `SourcePatternRegistry.initialize()`. That in turn calls `registerPatterns()` on each category registrar.

### Category Registrars

Each category has a registrar class that inherits from `BasePatternRegistrar`:

```swift
class CodeQuality: BasePatternRegistrar {
    override func registerPatterns() {
        registry.register(patterns: inlinePatterns)
        registerDelegatedPatterns()
    }
}
```

Individual rule registrars conform to `PatternRegistrarProtocol` and provide a `SyntaxPattern` — a value that names the rule and its associated visitor type:

```swift
struct ForceTry: PatternRegistrarProtocol {
    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .forceTry,
            visitor: ForceTryVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "...",
            suggestion: "...",
            description: "..."
        )
    }
}
```

---

## Rule Identification

Rules are identified by `RuleIdentifier`, a `CaseIterable` enum whose raw values are the human-readable display names (e.g. `"Force Try"`). This enum also provides:

- `category: PatternCategory` — which category the rule belongs to
- `suppressionKey: String` — kebab-case form for use in suppression comments (`"force-try"`)

`PatternCategory` is a separate enum with 12 cases that groups rules for category-level filtering.

---

## Inline Suppression

`InlineSuppressionParser` scans a file's source text for `// swiftprojectlint:` directives and produces an array of `SuppressionDirective` values. `InlineSuppressionFilter` converts those directives into closed line ranges keyed by `RuleIdentifier?` (nil = all rules), then removes any `LintIssue` whose line number falls within a suppressed range for its rule.

This runs inside `ProjectLinter.analyzeFile` immediately after visitor detection, before results are returned to the task group.

---

## Configuration

`LintConfiguration` is a value type (`struct`) that carries:

- `disabledRules: Set<RuleIdentifier>`
- `enabledOnlyRules: Set<RuleIdentifier>?`
- `excludedPaths: [String]`
- `ruleOverrides: [RuleIdentifier: RuleOverride]`

`LintConfigurationLoader` parses `.swiftprojectlint.yml` using Yams. Rule names in the YAML use the display name form (`"Force Try"`), which maps directly to `RuleIdentifier.rawValue`.

`LintConfiguration.resolveRules(cliCategories:cliRuleIdentifiers:)` computes the effective rule set by intersecting the config with any CLI overrides. `applyOverrides(to:projectRoot:)` runs after all detection is complete to apply severity changes and per-rule path exclusions.

---

## Cross-File Analysis

`CrossFileAnalysisEngine` runs after all per-file results are collected. It receives the full list of `ProjectFile` objects and the AST cache built during per-file analysis, and detects patterns that require comparing across files — for example, `Related Duplicate State Variable`, which flags a state variable name that appears in both a parent and child view.

Cross-file issues are appended to the per-file issues before `LintConfiguration.applyOverrides` runs. They are **not** subject to inline suppression, since a single-file comment cannot unambiguously target a multi-file issue.

---

## App Target

`Sources/App/` is a macOS SwiftUI application. It uses the same `Core` library as the CLI. Key components:

- `ContentViewModel` — drives analysis via `ProjectLinter`, holds observable state
- `LintResultsView` — displays issues grouped by category and severity
- `RuleSelectionDialog` — rule picker for enabling/disabling individual rules
- `RuleDocView` — displays per-rule documentation
- `SystemComponents` — app-wide shared state
- `DemoIssueGenerator` — produces hardcoded sample issues for UI demonstration without requiring a real project

## CLI Target

`Sources/CLI/` uses Swift Argument Parser. Key files:

- `SwiftProjectLintCLI.swift` — entry point, argument parsing, analysis orchestration
- `TextFormatter.swift` / `JSONFormatter.swift` — output formatting
- `ExitCodes.swift` — maps results to exit codes
- `CodableLintIssue.swift` / `LintReport.swift` — JSON output models
