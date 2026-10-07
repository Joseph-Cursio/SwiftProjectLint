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
1. FileAnalysisUtils        — discover .swift files: the reportable set (excluded paths and generated
                              files skipped), the evidence-only set, and the construction universe
                              (every .swift file the root compiles, no reporting filter at all)
2. Shared parse             — every file read and parsed once, on large-stack threads
                              (`LargeStackWorkers`); every stage below walks these trees — the
                              facts, every pre-scan collector, per-file and cross-file analysis
3. Package purity           — ConstructionFacts built from the universe's production sources,
                              sorted, then bound as `PackagePurity.current` around stages 4-6
4. Pre-scans                — collect cross-file type metadata (Identifiable, enum, actor types, all
                              local type names) and the purity catalogs (clean methods, the callee join)
5. Per-file analysis        — concurrent task group, one task per file:
       SourcePatternDetector      run visitors against the shared AST
       InlineSuppressionFilter    remove issues suppressed by comments
6. CrossFileAnalysisEngine  — detect issues that span multiple files
7. LintConfiguration        — apply per-rule severity overrides and path exclusions
```

Steps 1-5 happen in `ProjectLinter.swift` (SwiftProjectLintEngine); the shared parse and the universe are in `ProjectLinter+Purity.swift`, and the pre-scan catalogs, and how they reach each file's detector, are in `ProjectLinter+PreScan.swift`. Steps 6-7 happen after the task group collects all per-file results.

**Package purity.** On its own, SEI's purity oracle judges one declaration at a time, so `Item(n: n)` reads as pure even when `struct Item { let id = UUID() }` mints an identity on every construction. `PackagePurity` (SwiftProjectLintVisitors) holds SEI's `ConstructionFacts` — what constructing each package type runs — and is a task-local: `ProjectLinter.analyzeProject` binds it once, and every `PurityInferrer()` created inside the binding reads it, which is how the closure and kernel rules, the static candidacy helpers, the cross-file Could Be Private path and the two pre-scan catalogs all judge with one table. Which files count is `ConstructionUniverse`, a rule shared word for word with SwiftInferProperties (golden rows in `Docs/construction-universe.tsv`): production sources only, with no reporting filter — a nested package, a generated file or an excluded directory is still compiled code whose types production constructs. What bounds it is what the root compiles (`ProjectLinter.compiledByRoot`, run on a large-stack thread since it parses manifests): a nested package is a directory whose `Package.swift` is a manifest as SwiftPM reads one (a `// swift-tools-version` comment on the first non-blank line, any letter case, or on a later line from 6.0 — a source file, a directory or a dangling link of that name is none), and it is in only when it is reached — through `.package(path:)` dependencies read for their value and followed by path through every manifest reached (`Package.swift` and each `Package@swift-*.swift`), through a target `path:` inside it or holding it, or because the run reports on its files — or when the root gives no bound: no `Package.swift`, an `.xcodeproj` or `.xcworkspace` beside it, or doubt (a computed path, an unreadable manifest). References and packages are matched by canonical location (`realpath`: links and on-disk letter case). A symlinked file is classified where the link is, and two paths to one file are one entry; a file that is not strict UTF-8 is out; the macOS hidden flag is no reason to skip a file, a dot-prefixed name is. The rule and its amendments are shared with SwiftInferProperties, with the agreed cases in `Docs/construction-universe-cases.json`. Outside a binding (a single-file `SourcePatternDetector` run, a visitor test) the oracle is unconfigured.

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
├── MutatingMethodCollector.swift    │ (`mutating func` names, for Actor Reentrancy)
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
├── ProjectLinter+PreScan.swift     — pre-scan catalogs and their injection
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
