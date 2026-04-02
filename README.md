# THIS IS AN EXPERIMENT IN VIBE-CODING.
I'm letting AI do nearly all the work in generating code and tests.
I have tested examining rules and simulations out with a real project only a few times.
I've never looked at what the YAML part does (or does not do).
I allowed different AIs to hallucinate the market potential of this experiment.

# Swift Project Linter

A static analysis tool for SwiftUI projects that detects architectural issues, performance problems, and code quality concerns. Parses Swift source files using SwiftSyntax AST visitors to identify anti-patterns across 101 rules in 12 categories.

## Features

- **SwiftSyntax AST Analysis**: Precise, AST-based pattern detection — no regex
- **Cross-File Analysis**: Detects issues spanning multiple files (duplicate state, view hierarchies)
- **101 Lint Rules** across 12 categories
- **Three delivery targets**: macOS app GUI, CLI for CI/CD, and a reusable Core library
- **YAML configuration**: `.swiftprojectlint.yml` for per-project rule customization
- **Inline suppression**: `// swiftprojectlint:disable` comments for per-line control
- **Type-safe rule system**: `RuleIdentifier` enum for all rules and categories

## Targets

| Target | Type | Description |
|--------|------|-------------|
| `Core` | Library | Thin facade that re-exports all local packages |
| `App` | macOS App | SwiftUI interface with rule selection and results display |
| `CLI` | Executable | Command-line tool for CI/CD integration |

## CLI Usage

```bash
# Analyze a project (text output)
swift run CLI /path/to/project

# JSON output for CI integration
swift run CLI /path/to/project --format json

# Filter by category and severity threshold
swift run CLI /path/to/project --categories stateManagement performance --threshold error
```

## Rules

101 rules across 12 categories. See [Docs/rules/RULES.md](Docs/rules/RULES.md) for the full reference.

| Category | Rules |
|----------|-------|
| State Management | 8 |
| Performance | 8 |
| Animation | 10 |
| Architecture | 10 |
| Code Quality | 34 |
| Security | 2 |
| Accessibility | 6 |
| Memory Management | 2 |
| Networking | 2 |
| UI Patterns | 7 |
| Modernization | 12 |
| Other | 2 |

Rules marked **opt-in** are disabled by default and must be explicitly listed under `enabled_only` in `.swiftprojectlint.yml`.

## Architecture

### Package Structure

The project uses six local Swift packages under `Packages/`, with `Core` as a thin umbrella that re-exports them all via `@_exported import`.

```
SwiftProjectLint/
├── Package.swift
├── Sources/
│   ├── Core/              # Thin umbrella re-exporting all local packages
│   ├── App/               # macOS SwiftUI app
│   └── CLI/               # Command-line tool
├── Packages/
│   ├── SwiftProjectLintModels/    # Value types (LintIssue, RuleIdentifier, etc.)
│   ├── SwiftProjectLintVisitors/  # Base visitor infrastructure
│   ├── SwiftProjectLintRegistry/  # Pattern registration and detection engine
│   ├── SwiftProjectLintConfig/    # YAML config, file discovery, suppression
│   ├── SwiftProjectLintRules/     # All rule implementations by category
│   └── SwiftProjectLintEngine/    # Analysis pipeline orchestration
├── Tests/
│   ├── CoreTests/         # Lint rule unit tests
│   ├── AppTests/          # SwiftUI view tests (ViewInspector)
│   └── CLITests/          # CLI integration tests
└── Docs/
    ├── architecture.md    # Architecture deep-dive
    ├── reference.md       # CLI and configuration reference
    ├── user-guide.md      # User guide
    ├── tutorial.md        # Getting started tutorial
    └── rules/             # Per-rule documentation (101 files)
```

### Dependency Graph

```
SwiftProjectLintModels          (no dependencies)
        |
SwiftProjectLintVisitors        (+ SwiftSyntax)
        |
SwiftProjectLintRegistry        (+ SwiftSyntax)
    |           |
SwiftProjectLintConfig      SwiftProjectLintRules
    (+ Yams)                    (+ SwiftSyntax)
        |           |
SwiftProjectLintEngine
        |
       Core  <--  App / CLI
```

### Analysis Pipeline

```
1. File Discovery       -> FileAnalysisUtils finds all .swift files
2. Pre-scans            -> Collect cross-file type metadata
3. Per-file analysis    -> Concurrent task group, one task per file:
       Parser.parse()            parse source into AST
       SourcePatternDetector     run visitors against the AST
       InlineSuppressionFilter   remove suppressed issues
4. Cross-File Analysis  -> CrossFileAnalysisEngine detects multi-file issues
5. Configuration        -> Apply severity overrides and path exclusions
```

## Build & Test

```bash
# Build
swift build

# Run all tests
swift test

# Run a specific test suite
swift test --filter CoreTests.ArchitectureFatViewTests

# Run a specific test method
swift test --filter "CoreTests.ArchitectureFatViewTests/testFatViewDetection"

# Run with code coverage
swift test --enable-code-coverage
```

## Configuration

Create `.swiftprojectlint.yml` in your project root:

```yaml
# Disable specific rules
disabled_rules:
  - "Missing Documentation"
  - "TODO Comment"

# Or run only specific rules (mutually exclusive with disabled_rules)
enabled_only:
  - "Hardcoded Secret"
  - "Force Unwrap"
  - "Missing Accessibility Label"

# Exclude paths from all rules
excluded_paths:
  - "Tests/"
  - "Generated/"

# Per-rule overrides
rules:
  "Fat View":
    severity: info
  "Force Try":
    excluded_paths:
      - "LegacyViews/"
```

## Inline Suppression

```swift
// swiftprojectlint:disable:next force-try
let data = try! Data(contentsOf: url)

let threshold = 42 // swiftprojectlint:disable:this magic-number

// swiftprojectlint:disable force-try force-unwrap
let a = try! loadConfig()
let b = result!
// swiftprojectlint:enable force-try force-unwrap
```

## Severity Levels

- **Error**: Critical issues (e.g., hardcoded secrets, synchronous network calls)
- **Warning**: Issues that should be addressed (e.g., fat views, force unwrap, variable shadowing)
- **Info**: Style suggestions and best practices

## Dependencies

- [swift-syntax](https://github.com/apple/swift-syntax) `602.0.0` — AST parsing
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) `1.3.0+` — CLI
- [ViewInspector](https://github.com/nalexn/ViewInspector) `0.9.5+` — SwiftUI view testing
- [Yams](https://github.com/jpsim/Yams) `5.0.0+` — YAML config parsing

## Documentation

- [Docs/rules/RULES.md](Docs/rules/RULES.md) — Full rule reference (101 rules)
- [Docs/user-guide.md](Docs/user-guide.md) — User guide
- [Docs/architecture.md](Docs/architecture.md) — Architecture deep-dive
- [Docs/reference.md](Docs/reference.md) — CLI and configuration reference
- [Docs/tutorial.md](Docs/tutorial.md) — Getting started tutorial

## License

This project is for educational and demonstration purposes. Feel free to use and modify for your own projects.
