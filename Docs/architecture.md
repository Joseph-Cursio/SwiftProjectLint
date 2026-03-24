# SwiftProjectLint Architecture

This document describes how the codebase is organized and how its major components fit together.

---

## Package Structure

The project is a Swift Package with three targets:

```
Sources/
├── Core/      — analysis library, no UI dependencies
├── App/       — macOS SwiftUI application
└── CLI/       — command-line tool
```

`Core` is the only target with external library dependencies (SwiftSyntax, SwiftParser, Yams). `App` and `CLI` both import `Core` and add their own presentation layer on top.

---

## Analysis Pipeline

When `ProjectLinter.analyzeProject(at:)` is called, the following stages run in order:

```
1. FileAnalysisUtils        — discover .swift files, skip excluded paths and generated files
2. Pre-scans                — collect cross-file type metadata (Identifiable, enum, actor types)
3. Per-file analysis        — concurrent task group, one task per file:
       Parser.parse()             parse source into SourceFileSyntax (AST)
       SourcePatternDetector      run visitors against the AST
       InlineSuppressionFilter    remove issues suppressed by comments
4. CrossFileAnalysisEngine  — detect issues that span multiple files
5. LintConfiguration        — apply per-rule severity overrides and path exclusions
```

Steps 1–3 happen in `ProjectLinter.swift`. Steps 4–5 happen after the task group collects all per-file results.

---

## Core Directory Layout

```
Sources/Core/
├── Models/                     — value types shared across the system
│   ├── LintIssue.swift
│   ├── RuleIdentifier.swift
│   ├── PatternCategory.swift
│   ├── SyntaxPattern.swift
│   └── ProjectFile.swift
│
├── Configuration/              — YAML config loading and rule resolution
│   ├── LintConfiguration.swift
│   ├── LintConfigurationLoader.swift
│   └── LintConfigurationWriter.swift
│
├── Suppression/                — inline comment suppression
│   ├── InlineSuppressionParser.swift
│   └── InlineSuppressionFilter.swift
│
├── FileAnalysis/               — file discovery and path utilities
│   └── FileAnalysisUtils.swift
│
├── Visitors/                   — base visitor infrastructure
│   ├── BasePatternVisitor.swift
│   └── PatternVisitor.swift
│
├── SourceSyntaxPattern/        — registry and detection engine
│   ├── SourcePatternRegistry.swift
│   ├── PatternVisitorRegistry.swift
│   ├── SourcePatternDetector.swift
│   ├── PatternRegistrationProtocol.swift   ← PatternRegistrar, BasePatternRegistrar
│   └── PatternVisitorRegistryProtocol.swift
│
├── PatternRegistryFactory.swift  — factory for creating configured systems
├── ProjectLinter.swift           — top-level analysis orchestrator
├── AdvancedAnalyzer.swift        — higher-level analysis API
│
├── CrossFileAnalysis/          — multi-file relationship detection
│
├── StateAnalysis/              — state variable collection utilities
│
│   (one directory per rule category)
├── StateManagement/
│   ├── Visitors/
│   └── PatternRegistrars/
├── Performance/
├── Animation/
├── Architecture/
├── CodeQuality/
├── Security/
├── Accessibility/
├── MemoryManagement/
├── Networking/
├── UI/
└── Modernization/
```

Each category directory follows the same layout: a `Visitors/` folder containing `SyntaxVisitor` subclasses and a `PatternRegistrars/` folder containing the objects that register those visitors with the pattern registry.

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

The registry system decouples visitor classes from the detection engine:

```
PatternVisitorRegistry   — maps SyntaxPattern → visitor type
SourcePatternRegistry    — holds all registered SyntaxPattern values
SourcePatternDetector    — creates visitor instances and drives the walk
```

Registration happens at startup via `PatternRegistryFactory.createConfiguredSystem()`, which calls `SourcePatternRegistry.initialize()`. That in turn calls `registerPatterns()` on each category registrar.

### Category Registrars

Each category has a registrar class that inherits from `BasePatternRegistrar`:

```swift
class CodeQualityRegistrar: BasePatternRegistrar {
    override func registerPatterns() {
        registry.register(pattern: MagicNumberRegistrar().pattern)
        registry.register(pattern: HardcodedStringRegistrar().pattern)
        // ...
    }
}
```

Individual rule registrars conform to `PatternRegistrar` and provide a `SyntaxPattern` — a value that names the rule and its associated visitor type:

```swift
struct ForceTryRegistrar: PatternRegistrar {
    var pattern: SyntaxPattern {
        SyntaxPattern(ruleIdentifier: .forceTry, visitorType: ForceTryVisitor.self)
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

- `ContentView` — main window with project path input and analysis trigger
- `ContentViewModel` — drives analysis via `ProjectLinter`, holds observable state
- `LintResultsView` — displays issues grouped by category and severity
- `DemoIssueGenerator` — produces hardcoded sample issues for UI demonstration without requiring a real project

## CLI Target

`Sources/CLI/SwiftProjectLintCLI.swift` — a single file using Swift Argument Parser. It parses arguments, loads configuration, calls `ProjectLinter.analyzeProject`, formats output via `TextFormatter` or `JSONFormatter`, and maps the results to an exit code via `ExitCodes`.
