# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Build the project
swift build

# Run all tests
swift test

# Run a specific test file
swift test --filter SwiftProjectLintCoreTests.ArchitectureFatViewTests

# Run a specific test method
swift test --filter "SwiftProjectLintCoreTests.ArchitectureFatViewTests/testFatViewDetection"

# Resolve dependencies after modifying Package.swift
swift package resolve

# Run SwiftLint on the project
swiftlint

# Run SwiftLint with autocorrect
swiftlint --fix

# Run tests with code coverage
swift test --enable-code-coverage

# View code coverage report (after running tests with coverage)
xcrun llvm-cov report .build/debug/SwiftProjectLintPackageTests.xctest/Contents/MacOS/SwiftProjectLintPackageTests -instr-profile .build/debug/codecov/default.profdata

# Export code coverage to lcov format
xcrun llvm-cov export .build/debug/SwiftProjectLintPackageTests.xctest/Contents/MacOS/SwiftProjectLintPackageTests -instr-profile .build/debug/codecov/default.profdata -format=lcov > coverage.lcov
```

Note: UI tests are configured in the Xcode project and should be run through Xcode, not SPM.

## Project Architecture

### Two-Target Structure

- **SwiftProjectLintCore** (`Sources/SwiftProjectLintCore/`): Core analysis library containing all linting logic, visitors, and pattern detection
- **SwiftProjectLint** (`Sources/SwiftProjectLint/`): macOS app executable with SwiftUI interface

### Core Analysis Pipeline

1. **File Discovery**: `FileAnalysisUtils` finds Swift files in a project
2. **AST Parsing**: SwiftSyntax parses each file into an AST
3. **Pattern Detection**: Specialized visitors traverse the AST detecting issues
4. **Cross-File Analysis**: `CrossFileAnalysisEngine` detects issues spanning multiple files (duplicate state, view hierarchies)
5. **Issue Aggregation**: Results collected into `LintIssue` objects

### Visitor Architecture

The linting engine uses the SwiftSyntax visitor pattern. All visitors inherit from `BasePatternVisitor` which extends `SyntaxVisitor`:

```
Sources/SwiftProjectLintCore/
├── Visitors/
│   ├── BasePatternVisitor.swift    # Base class with common utilities
│   └── PatternVisitor.swift        # Protocol definition
├── Accessibility/Visitors/         # Accessibility checking visitors
├── Architecture/Visitors/          # Architecture pattern visitors
├── CodeQuality/Visitors/           # Code quality visitors
├── Performance/Visitors/           # Performance anti-pattern visitors
├── Security/Visitors/              # Security issue visitors
├── StateManagement/Visitors/       # State variable analysis
└── UI/Visitors/                    # UI pattern visitors
```

Each category also has a `PatternRegistrars/` folder containing pattern registration logic.

### Type-Safe Rule System

Rules are identified by the `RuleIdentifier` enum (not strings). Each rule maps to a `PatternCategory`:
- `.stateManagement`, `.performance`, `.architecture`, `.codeQuality`
- `.security`, `.accessibility`, `.memoryManagement`, `.networking`
- `.uiPatterns`, `.animation`, `.other`

Pattern registration uses `SwiftSyntaxPatternRegistry` (singleton) and `SourcePatternRegistry`.

### Key Entry Points

- **ProjectLinter**: High-level API for analyzing entire projects
- **AdvancedAnalyzer**: Sophisticated architectural analysis
- **SwiftSyntaxPatternDetector**: Direct AST-based pattern detection
- **CrossFileAnalysisEngine**: Multi-file relationship analysis

## Coding Conventions

- Use `RuleIdentifier` enum cases directly (not `RuleIdentifier(rawValue:)`)
- Pattern visitors should inherit from `BasePatternVisitor`
- New rules need: a visitor, a pattern registrar entry, and a `RuleIdentifier` case
- Tests are organized to mirror the source structure under `Tests/SwiftProjectLintCoreTests/`

## Known Technical Debt

Per project documentation:
- Some property wrapper and view type detection still uses string comparisons (migration in progress)
- Several large files need splitting (see `__refactor.md`)
- Async/await conversion incomplete; AST caching not implemented
