# THIS IS AN EXPERIMENT IN VIBE-CODING.
I'm letting AI do nearly all the work in generating code and tests.
I have tested examing rules and simulations out with a real project only a few times.
I've never looked at what the YAML part does (or does not do).
I allowed different AIs to hallucinate the market potential of this experiment.

# Swift Project Linter

A static analysis tool for SwiftUI projects that detects architectural issues, performance problems, and code quality concerns. Parses Swift source files using SwiftSyntax AST visitors to identify anti-patterns across 97 rules in 11 categories.

## Features

- **SwiftSyntax AST Analysis**: Precise, AST-based pattern detection — no regex
- **Cross-File Analysis**: Detects issues spanning multiple files (duplicate state, view hierarchies)
- **97 Lint Rules** across 11 categories
- **Three delivery targets**: macOS app GUI, CLI for CI/CD, and a reusable Core library
- **YAML configuration**: `.swiftprojectlint.yml` for per-project rule customization
- **Type-safe rule system**: `RuleIdentifier` enum for all rules and categories

## Targets

| Target | Type | Description |
|--------|------|-------------|
| `Core` | Library | All analysis logic, visitors, pattern detection |
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

97 rules across 11 categories. See [Docs/rules/RULES.md](Docs/rules/RULES.md) for the full reference.

| Category | Rules |
|----------|-------|
| State Management | 8 |
| Performance | 8 |
| Animation | 10 |
| Architecture | 10 |
| Code Quality | 31 |
| Security | 2 |
| Accessibility | 6 |
| Memory Management | 2 |
| Networking | 2 |
| UI Patterns | 7 |
| Modernization | 12 |

Rules marked **opt-in** are disabled by default and must be explicitly listed under `enabled_only` in `.swiftprojectlint.yml`.

## Architecture

### Package Structure

```
SwiftProjectLint/
├── Package.swift
├── Sources/
│   ├── Core/              # Thin umbrella re-exporting SwiftProjectLintEngine
│   ├── App/               # macOS SwiftUI app
│   └── CLI/               # Command-line tool
├── Packages/              # Local SPM packages
│   ├── SwiftProjectLintEngine/    # Analysis pipeline orchestration
│   ├── SwiftProjectLintVisitors/  # SwiftSyntax visitor implementations
│   ├── SwiftProjectLintRules/     # Rule definitions and registrars
│   ├── SwiftProjectLintRegistry/  # Pattern registration
│   ├── SwiftProjectLintModels/    # Shared types (LintIssue, RuleIdentifier, etc.)
│   └── SwiftProjectLintConfig/    # YAML config loading
├── Tests/
│   ├── CoreTests/         # Lint rule unit tests
│   ├── AppTests/          # SwiftUI view tests (ViewInspector)
│   └── CLITests/          # CLI integration tests
└── Docs/rules/            # Per-rule documentation
```

### Analysis Pipeline

```
1. File Discovery       → FileAnalysisUtils finds all .swift files
2. AST Parsing          → SwiftParser parses each file (no throws)
3. Visitor Dispatch     → Specialized visitors traverse the AST
4. Cross-File Analysis  → CrossFileAnalysisEngine detects multi-file issues
5. Issue Aggregation    → Results collected as LintIssue objects
```

### Visitor Categories

Visitors live in `Packages/SwiftProjectLintVisitors/` organized by category:

- **State Management**: property wrapper analysis, duplicate/unused state detection
- **Performance**: expensive view body operations, ForEach ID issues, ViewBuilder complexity
- **Animation**: deprecated APIs, excessive springs, conflicting animations
- **Architecture**: fat views, singleton usage, dependency injection, protocol soup
- **Code Quality**: naming conventions, force unwrap/try, actor reentrancy, async patterns
- **Security**: hardcoded secrets, unsafe URLs
- **Accessibility**: missing labels/hints, color contrast, font sizes
- **Memory Management**: retain cycles, large objects in state
- **Networking**: missing error handling, synchronous calls
- **UI Patterns**: nested navigation, missing previews, modifier order
- **Modernization**: legacy APIs (DispatchQueue, NotificationCenter, ObservableObject)

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
  - missing_documentation
  - todo_comment

# Or run only specific rules
enabled_only:
  - hardcoded_secret
  - force_unwrap
  - missing_accessibility_label

# Exclude paths
excluded:
  - Pods
  - .build
  - Generated
```

## Severity Levels

- **Error**: Critical issues (e.g., hardcoded secrets, synchronous network calls)
- **Warning**: Issues that should be addressed (e.g., fat views, force unwrap)
- **Info**: Style suggestions and best practices

## Dependencies

- [swift-syntax](https://github.com/apple/swift-syntax) `602.0.0` — AST parsing
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) `1.3.0+` — CLI
- [ViewInspector](https://github.com/nalexn/ViewInspector) `0.9.5+` — SwiftUI view testing
- [Yams](https://github.com/jpsim/Yams) `5.0.0+` — YAML config parsing

## Related Documentation

- [Docs/rules/RULES.md](Docs/rules/RULES.md) — Full rule reference (97 rules)
- [Docs/user-guide.md](Docs/user-guide.md) — User guide
- [Docs/architecture.md](Docs/architecture.md) — Architecture deep-dive
- [Docs/tutorial.md](Docs/tutorial.md) — Getting started tutorial

## License

This project is for educational and demonstration purposes. Feel free to use and modify for your own projects.
