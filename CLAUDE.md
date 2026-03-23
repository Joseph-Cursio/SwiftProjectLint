# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Build the project
swift build

# Run all tests
swift test

# Run a specific test file
swift test --filter CoreTests.ArchitectureFatViewTests

# Run a specific test method
swift test --filter "CoreTests.ArchitectureFatViewTests/testFatViewDetection"

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

# Run ViewInspector UI tests (SwiftUI view tests)
swift test --filter AppTests

# Run a specific ViewInspector test
swift test --filter "AppTests.ContentViewTests"
swift test --filter "AppTests.LintResultsViewTests"

# Run the CLI tool
swift run CLI /path/to/project

# CLI with JSON output
swift run CLI /path/to/project --format json

# CLI with specific categories and error-only threshold
swift run CLI /path/to/project --categories stateManagement performance --threshold error

# Run CLI tests
swift test --filter CLITests
```

**Note on UI Testing:**
- **ViewInspector tests** (`Tests/AppTests/`): Run via SPM with `swift test`. These test SwiftUI view structure, content, and interactions.
- **XCUITest tests** (`Tests/UITests/`): Run through Xcode only. These are integration tests for the full app.

## Project Architecture

### Three-Target Structure

- **Core** (`Sources/Core/`): Core analysis library containing all linting logic, visitors, and pattern detection
- **App** (`Sources/App/`): macOS app executable with SwiftUI interface
- **CLI** (`Sources/CLI/`): Command-line tool for CI/CD integration with text and JSON output

### Core Analysis Pipeline

1. **File Discovery**: `FileAnalysisUtils` finds Swift files in a project
2. **AST Parsing**: SwiftSyntax parses each file into an AST
3. **Pattern Detection**: Specialized visitors traverse the AST detecting issues
4. **Cross-File Analysis**: `CrossFileAnalysisEngine` detects issues spanning multiple files (duplicate state, view hierarchies)
5. **Issue Aggregation**: Results collected into `LintIssue` objects

### Visitor Architecture

The linting engine uses the SwiftSyntax visitor pattern. All visitors inherit from `BasePatternVisitor` which extends `SyntaxVisitor`:

```
Sources/Core/
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

## UI Testing with ViewInspector

The project uses [ViewInspector](https://github.com/nalexn/ViewInspector) for SwiftUI view testing. Tests are in `Tests/AppTests/`.

### Writing ViewInspector Tests

```swift
import Testing
import SwiftUI
import ViewInspector
@testable import App

@Suite
@MainActor
struct MyViewTests {
    @Test
    func testViewStructure() throws {
        let view = MyView()
        let inspected = try view.inspect()

        // Find specific view types
        let texts = try inspected.findAll(ViewType.Text.self)
        let buttons = try inspected.findAll(ViewType.Button.self)

        // Check text content
        let textStrings = texts.compactMap { try? $0.string() }
        #expect(textStrings.contains("Expected Text"))

        // Find nested views
        let vStack = try inspected.find(ViewType.VStack.self)
        _ = try vStack.find(MyChildView.self)
    }

    @Test
    func testWithEnvironmentObject() throws {
        let systemComponents = SystemComponents()
        systemComponents.initialize()
        let view = ContentView().environmentObject(systemComponents)
        let inspected = try view.inspect()
        // ... assertions
    }
}
```

### Common ViewInspector Patterns

- **Finding views**: `inspected.find(ViewType.Button.self)`, `inspected.findAll(ViewType.Text.self)`
- **Checking text**: `try text.string()` returns the text content
- **Navigation**: `inspected.navigationView().vStack()` to navigate hierarchy
- **Custom views**: `try inspected.find(MyCustomView.self)`
- **Lists/Sections**: `try list.section(0)`, `try forEach.view(MyRow.self, 0)`

### Test File Locations

- `Tests/AppTests/ContentViewTests.swift` - Main view tests
- `Tests/AppTests/LintResultsViewTests.swift` - Results display tests
- `Tests/AppTests/RuleSelectionDialogTests.swift` - Dialog tests
- `Tests/AppTests/ContentView*Tests.swift` - Component tests

## Coding Conventions

- Use `RuleIdentifier` enum cases directly (not `RuleIdentifier(rawValue:)`)
- Pattern visitors should inherit from `BasePatternVisitor`
- New rules need: a visitor, a pattern registrar entry, and a `RuleIdentifier` case
- Tests are organized to mirror the source structure under `Tests/CoreTests/`
- UI tests use Swift Testing framework (`@Test`, `#expect`) with ViewInspector

## Known Technical Debt

Per project documentation:
- Some property wrapper and view type detection still uses string comparisons (migration in progress)
- Several large files need splitting (see `__refactor.md`)
- Async/await conversion complete; AST caching implemented (in-memory, per-analysis-run)
