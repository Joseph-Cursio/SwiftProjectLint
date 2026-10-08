# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Build the project
swift build

# Run all tests
swift test

# The whole suite is ~3100 tests in ~6 seconds. Just run `swift test`.
#
# It used to take ~900s and often never finished, which made skipping
# AppTests look necessary. The cause was three tests in ContentViewModelTests
# pointing the linter at `FileManager.default.temporaryDirectory` *itself* —
# shared machine state holding 26,000+ Swift files on a developer machine,
# every one of them parsed through SwiftSyntax. Fixed by giving those tests
# their own directories. If a run ever crawls again, suspect a test analysing
# a directory it does not own, not the suite being inherently slow.

# Run every test EXCEPT AppTests (rarely needed now — see above)
swift test --skip AppTests

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

1. **File Discovery**: `FileAnalysisUtils` finds Swift files in a project — the reportable set, the evidence-only set (excluded paths), and — only when a planned visitor declares a purity input (see **Purity gate** below) — the construction universe (every Swift file the root compiles, no reporting filter: a nested package — a directory whose `Package.swift` is a manifest as SwiftPM reads one: a `// swift-tools-version` comment on the first non-blank line in any case, or on a later line from 6.0 (`ConstructionUniverse.isManifest`) — only when the root's closure reaches it (`.package(path:)` values and target `path:`s that hold it or lie in it, through `Package.swift` and `Package@swift-*.swift`, matched by canonical path) or the run reports on it, every one when the root has no manifest, has an `.xcodeproj`/`.xcworkspace` beside it, or doubt arises; a symlink classified where the link is; strict UTF-8 only; the UF_HIDDEN flag ignored)
2. **AST Parsing**: SwiftSyntax parses each file once (`ProjectLinter.parseOnce`); every later phase walks those same trees — the package purity, every pre-scan collector (`collectTypes` and the body-needing catalogs), per-file and cross-file analysis
3. **Package Purity**: `PackagePurity.build` turns the universe's production sources (`ConstructionUniverse`) into SEI's `ConstructionFacts`, bound as the task-local `PackagePurity.current` around phases 4-6 — every `PurityInferrer()` created inside reads it. Built only when discovery resolved a universe; otherwise `PackagePurity.withheld(by:)` is bound instead
4. **Pre-scan**: `CollectedTypes.collect` builds the cross-file catalogs (`ProjectLinter+PreScan.swift`); the two purity catalogs (`CleanInstanceMethodCatalog`, `ImpurePackageFunctions`) only when demanded, otherwise `.withheld(by:)`
5. **Pattern Detection**: Specialized visitors traverse the AST detecting issues
6. **Cross-File Analysis**: `CrossFileAnalysisEngine` detects issues spanning multiple files (duplicate state, view hierarchies)
7. **Issue Aggregation**: Results collected into `LintIssue` objects

Never create a `PurityInferrer` another way (SEI's directly, or `init(context:)` in `Sources/`), move analysis work off the task tree (`Task.detached`, dispatch queues), or keep an oracle in a `static`: each makes some verdicts in a run ignore the run's facts. `PurityOracleEntryTests` checks all three. Its one named exception is `LargeStackWorkers`, the 64 MB-stack threads that run only the shared parse, the facts build and the universe's manifest reads (`compiledUniverse`), before the binding: a deep file (a 1,000-arm `else if`, a 10,000-link member chain) overflows a cooperative thread's 512 KB and kills the process. The universe rule, `Docs/construction-universe.tsv` and `Docs/construction-universe-cases.json` are shared with SwiftInferProperties (byte-identical copies) — change both together; that includes the spec's amendments (`ConstructionUniverse.localPackageDependencies(manifest:)` and the nested-package bound, link-location classification, strict UTF-8, and `ConstructionUniverse.buildOrder`, the one order the facts are built in; then amendments 3, 3b and 4: what a manifest is (`isManifest`, `manifest(inDirectory:)`, `manifests(inDirectory:)`), an Xcode project beside it, literal values and canonical matching, the closure by path, reported packages, `localTargetPaths(manifest:)`, manifests on large stacks, and the hidden flag). Accepted gaps, documented on the Pure Function page: a `Package.swift` source file or `*Tests` folder inside a production target is dropped (SwiftPM compiles both), namesakes across modules in one universe over-refute, symlinked directories are not followed, a symlinked package's relative dependencies are resolved from the link's target, not where it sits, and a target reaches a nested package only through its literal `path:` (not SwiftPM's default `Sources/<name>`, nor through a symlink below the path).

**Purity gate.** A run builds the universe, the table and the two pre-scan purity catalogs only when a visitor it will execute reads them. `PurityDemand` (`ProjectLinter+PurityGate.swift`) is the union of `packagePurityInputs` over every registered pattern whose rule `resolveRules` plans — which is why the rules are resolved before discovery (`DiscoveredProject.effectiveRules`). What is not built is withheld, and every read of a withheld value trips the pass's `PurityTripwire`. A tripped pass's findings are discarded and the run is done once more with everything built (even when the task was cancelled), so the reported findings never change: a missed declaration costs a second pass, never a finding, and shows as the `assert` in `analyzeProject` in debug and a `warning:` on the CLI's stderr (`ProjectLinter.init(purityRerunNotice:)`). So a visitor that creates a `PurityInferrer` (directly, or through an entry point in `PurityOracleEntryTests.oracleEntryPoints` such as `PropertyTestCandidacy.candidate`/`shape`), or reads `knownCleanInstanceMethods` or `knownImpurePackageFunctions`, must conform to `PackagePurityConsumer` with the inputs it reads. A value derived from the purity lives in a `Withholdable`, whose state is private to its file so every read goes through `read(_:)`; never keep a `PurityTripwire`, a `Withholdable` or a value that holds one (the two catalogs, `PackagePurityJoin`, `CollectedTypes`, the `SourcePatternDetector`, a visitor) in a `static`. `noStaticHoldsAnOracle` enforces that by type name — the oracle, the table, those types, every withholdable surface and every `BasePatternVisitor` subclass, found from the source — so any other type that stores one is not held until it is added to `heldByOneRun` (`DiscoveredProject`, `PatternDetectionSystem`, `FileAnalysisEnvironment` and `any SourcePatternDetectorProtocol` are not), and a static whose type is inferred from a call (`static var last = makeCatalog()`) is not seen at all. `PurityGateDeclarationTests` runs every rule alone with exactly its declared demand and fails on an undeclared read, naming the rule, and on a declared input never read; `PurityGateSurfaceTests` pins what counts as a read; `PurityOracleEntryTests+Gate` checks the source (`purityReadersDeclareWhatTheyRead` fails on a rule file that names a purity surface a visitor it declares or extends does not declare, even when no corpus reaches it), `oracleEntryPointsAreKnown` finds every public Visitors declaration that creates an oracle, declaration by declaration, and fails when the list disagrees, and `PurityScanProbeTests` hands each scan the code it must catch. Default runs build everything: the nine reading rules are on by default.

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

Pattern registration uses `SourcePatternRegistry` and `PatternVisitorRegistry`, both in
`Packages/SwiftProjectLintRegistry/` and both offering a `.shared` singleton alongside a plain
`init` for injection. `SourcePatternRegistry` drives `initialize()` and category-factory
registration (`registerFactory`), and delegates all pattern storage to `PatternVisitorRegistry`,
which indexes visitors by `PatternCategory`.

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
- A new rule whose visitor reads package purity (an oracle, `knownCleanInstanceMethods`, `knownImpurePackageFunctions`) also conforms it to `PackagePurityConsumer` — see **Purity gate**; `PurityGateDeclarationTests` names the rule if it forgets
- **After adding a `RuleIdentifier` case, run `swift package clean`.** A new case shifts the ordinal of every case after it, and SPM's incremental build can leave dependent modules resolving the old positions. Appending to the end of a *category block* does not avoid this: every block is followed by later categories and the `fileParsingError` / `unknown` sentinels, so any new rule is a mid-enum insertion. (This file used to say appending needed no clean; the first two rules added that way both hit the stale build.) The pre-commit hook cleans before testing, so a commit is safe either way; the clean matters for the `swift test` you run while working. The tell that you needed one is rule-identity assertions failing in modules you never touched: e.g. `DemoIssueGeneratorTests` reporting rules that its static dictionary literal does not name. A literal cannot emit a value it doesn't name, so that symptom is always a stale build, never a logic bug; don't debug the failing tests
- Registrar style: a rule with its own **single-purpose visitor** gets its own leaf registrar — a `struct` conforming to `PatternRegistrarProtocol` that supplies one `var pattern` — wired in via the category registrar's `register(registrars:)` list. Rules that **share a multi-purpose category visitor** (e.g. `PerformanceVisitor`, `AccessibilityVisitor`, `UIVisitor`, `NamingConventionVisitor`) stay inline in that category's `register(patterns:)` array, since one visitor emits several rule names. (Both styles are functionally identical; a few single-purpose rules predate this convention and remain inline — that's fine, not a bug.)
- Tests are organized to mirror the source structure under `Tests/CoreTests/`
- UI tests use Swift Testing framework (`@Test`, `#expect`) with ViewInspector
- In `#expect`, avoid leading `!` — use `== false` instead: `#expect(x.isEmpty == false)` not `#expect(!x.isEmpty)`. The `!` form produces noisy failure output (`!((x → []).isEmpty → true → true)`); the `== false` form gives clean diagnostics (`(x.isEmpty → true) == false`)

## Known Technical Debt

Per project documentation:
- Some property wrapper and view type detection still uses string comparisons (migration in progress)
- Several large files need splitting (see `__refactor.md`)
- Async/await conversion complete; AST caching implemented (in-memory, per pass): one parse per file per pass — a run the purity gate redoes parses again in its second pass — shared by the package purity, every pre-scan collector (the `collectTypes` name sets and the body-needing catalogs), per-file analysis and cross-file analysis
