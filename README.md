# THIS IS AN EXPERIMENT IN VIBE-CODING.
I'm letting AI do nearly all the work in generating code and tests. 
I have tested examing rules and simulations out with a real project only a few times.
I've never looked at what the YAML part does (or does not do).
I allowed different AIs to hallucinate the market potential of this experiment.

# Swift Project Linter

A comprehensive SwiftUI project analyzer that detects architectural issues, performance problems, and code quality concerns across your entire SwiftUI project. This tool helps maintain clean architecture by identifying problems like duplicate state variables, inefficient patterns, and architectural anti-patterns using SwiftSyntax-based analysis.

## 🎯 Key Features

### Multi-Layer Analysis
- **SwiftSyntax Analysis**: Advanced architectural analysis using SwiftSyntax for precise parsing
- **Cross-File Analysis**: Identifies issues spanning multiple files and view relationships
- **View Hierarchy Mapping**: Builds complete view relationship graphs
- **Pattern-Based Detection**: 50+ patterns across 9 categories for comprehensive code analysis
- **Type-Safe Detection**: Enum-based pattern detection for improved accuracy and maintainability (rules/categories; property wrapper/view type logic is still being migrated)

### Detection Categories

#### 1. **State Management (4 patterns)**
- Duplicate state variables across related views
- Missing @StateObject usage for ObservableObjects
- Unused state variables
- Uninitialized state variables

#### 2. **Performance (4 patterns)**
- Expensive operations in view body
- ForEach without proper ID usage
- Large view bodies (>500 characters)
- Unnecessary view updates

#### 3. **Architecture (4 patterns)**
- Fat views with too many state variables
- Missing dependency injection
- Circular dependencies
- Missing protocol abstractions

#### 4. **Code Quality (4 patterns)**
- Magic numbers and hardcoded values
- Long functions and complex expressions
- Missing documentation
- Inconsistent naming conventions

#### 5. **Security (2 patterns)**
- Hardcoded secrets and credentials
- Unsafe URL construction

#### 6. **Accessibility (2 patterns)**
- Missing accessibility labels
- Missing accessibility hints

#### 7. **Memory Management (2 patterns)**
- Potential retain cycles
- Large objects in state

#### 8. **Networking (2 patterns)**
- Missing error handling
- Synchronous network calls

#### 9. **UI Patterns (3 patterns)**
- Nested navigation structures
- Missing preview providers
- Inconsistent styling

## 🏗️ Architecture

### Core Components

1. **ProjectLinter**: File analysis and state variable extraction using SwiftSyntax
2. **AdvancedAnalyzer**: Sophisticated architectural analysis using SwiftSyntax
3. **SwiftSyntaxPatternDetector**: AST-based pattern detection using SwiftSyntax
4. **SwiftSyntaxPatternRegistry**: Centralized pattern registration and management
5. **ContentView**: Main SwiftUI interface with rule selection and analysis
6. **LintResultsView**: Results display with expandable issue details

### SwiftSyntax Visitors

The project includes specialized SwiftSyntax visitors for precise analysis:

- **SwiftUIManagementVisitor**: Analyzes property wrappers and state patterns
- **PerformanceVisitor**: Detects performance anti-patterns in view bodies
- **ArchitectureVisitor**: Identifies architectural issues and fat views
- **CodeQualityVisitor**: Checks code style and quality patterns
- **SecurityVisitor**: Detects security-related issues
- **AccessibilityVisitor**: Analyzes accessibility patterns
- **MemoryManagementVisitor**: Identifies memory-related issues
- **NetworkingVisitor**: Detects networking anti-patterns
- **UIVisitor**: Analyzes UI patterns including navigation
- **ViewRelationshipVisitor**: Maps view hierarchies and relationships
- **StateVariableVisitor**: Extracts and analyzes state variables
- **ForEachSelfIDVisitor**: Detects ForEach performance issues

### Analysis Pipeline

```
1. File Discovery → Find all Swift files in project
2. SwiftSyntax Analysis → Parse AST for architectural analysis
3. Pattern Detection → Apply 50+ patterns across 9 categories
4. View Hierarchy Building → Map parent-child relationships
5. Cross-File Analysis → Detect duplicates and patterns
6. Issue Generation → Create actionable suggestions
```

## 🚀 Usage

### Basic Usage
```swift
let linter = ProjectLinter()
let issues = linter.analyzeProject(at: "/path/to/your/project")
```

### Advanced Analysis
```swift
let analyzer = AdvancedAnalyzer()
let architectureIssues = analyzer.analyzeArchitecture(projectPath: "/path/to/your/project")
```

### SwiftSyntax Analysis
```swift
let swiftSyntaxDetector = SwiftSyntaxPatternDetector()
let astIssues = swiftSyntaxDetector.detectPatterns(in: sourceCode, filePath: filePath)
```

### Pattern-Based Detection
```swift
let detector = SwiftSyntaxPatternDetector()
let patternIssues = detector.detectPatterns(in: fileContent, filePath: filePath)
```

### UI Integration
```swift
ContentView() // Main interface with rule selection
LintResultsView(issues: issues) // Results display
```

## 📋 Example Issues Detected

### Warning: Duplicate State
```
⚠️ Duplicate state variable 'isLoading' found in ParentView and ChildView
   File: ExampleViews/ParentView.swift:5
   Suggestion: Create a shared ObservableObject for 'isLoading' and pass it 
   from ParentView to ChildView using @ObservedObject.
```

### Performance: Expensive Operation
```
⚠️ Expensive collection operations detected in view body
   File: ExampleViews/PerformanceIssuesView.swift:23
   Suggestion: Move expensive operations outside the view body or use @State to cache results
```

### Architecture: Fat View
```
⚠️ View 'ComplexView' has too many state variables, consider MVVM pattern
   File: ExampleViews/ArchitectureIssuesView.swift:15
   Suggestion: Extract business logic into an ObservableObject ViewModel
```

### Accessibility: Missing Label
```
⚠️ Button with image missing accessibility label
   File: ExampleViews/AccessibilityIssuesView.swift:8
   Suggestion: Add .accessibilityLabel() to make the button accessible
```

## 🎨 UI Features

- **Rule Selection**: Customizable detection patterns with 9 categories
- **Directory Selection**: Native macOS file picker for project selection
- **Real-time Analysis**: Progress indicators during analysis
- **Expandable Results**: Detailed issue breakdown with file locations
- **Severity Indicators**: Color-coded icons for different issue types
- **Persistent Settings**: Rule preferences saved across app launches
- **SwiftSyntax Analysis**: Advanced AST-based pattern detection

## 🔧 Configuration

### Customizing Detection Rules

The app includes a rule selection interface where you can enable/disable specific patterns:

```swift
// Access patterns by category
SwiftSyntaxPatternRegistry.shared.getPatterns(for: .stateManagement)
SwiftSyntaxPatternRegistry.shared.getPatterns(for: .performance)
SwiftSyntaxPatternRegistry.shared.getPatterns(for: .architecture)
// ... and 6 more categories
```

### Adding Custom Patterns

```swift
let pattern = SyntaxPattern(
    name: "Custom SwiftSyntax Pattern",
    visitor: CustomVisitor.self,
    severity: .warning,
    category: .stateManagement,
    messageTemplate: "Custom message with {variableName}",
    suggestion: "How to fix it",
    description: "Detailed description"
)

SwiftSyntaxPatternRegistry.shared.register(pattern: pattern)
```

### Severity Levels

- **Error**: Critical issues that should be fixed immediately
- **Warning**: Issues that should be addressed but don't break functionality  
- **Info**: Suggestions for improvement and best practices

## 🛠️ Technical Implementation

### SwiftSyntax Analysis
Advanced parsing using SwiftSyntax for:
- Precise AST traversal
- View relationship detection
- State variable analysis
- Cross-file architectural patterns
- Context-aware pattern detection

### Pattern Detection
Uses SwiftSyntax visitors to identify SwiftUI and Swift code patterns:
- Property wrapper detection: `@State`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject`
- Performance anti-patterns: expensive operations, large view bodies
- Architecture issues: fat views, missing dependencies
- Code quality: magic numbers, missing documentation

### View Relationship Analysis
Detects parent-child relationships through:
- Direct view instantiation: `ChildView()`
- Navigation: `NavigationLink(destination: ChildView())`
- Sheets: `.sheet(content: ChildView())`
- Full-screen covers: `.fullScreenCover(content: ChildView())`
- Popovers: `.popover(content: ChildView())`
- Alerts: `.alert(content: AlertView())`

### Type-Safe Pattern Detection
The project uses enum-based pattern detection for improved accuracy:
- **RuleIdentifier enum**: Type-safe rule identification and category mapping
- **PropertyWrapper enum**: Type-safe property wrapper detection
- **SwiftUIViewType enum**: Type-safe view type identification
- **ASTNodeType enum**: Type-safe AST node analysis
- **RelationshipType enum**: Type-safe relationship mapping
- **PatternCategory enum**: Type-safe pattern categorization

## 🎯 Best Practices

### State Management
1. **Single Source of Truth**: Each piece of state should have one owner
2. **Proper Property Wrappers**: Use @StateObject for owned objects, @ObservedObject for passed objects
3. **Environment Objects**: Use @EnvironmentObject for widely shared state
4. **State Lifting**: Move shared state up the view hierarchy

### Architecture Patterns
1. **MVVM**: Separate business logic into ObservableObject classes
2. **Dependency Injection**: Pass dependencies explicitly or via environment
3. **View Composition**: Break complex views into smaller, focused components
4. **State Isolation**: Keep view-specific state local, share only what's necessary

### Performance Optimization
1. **Avoid Expensive Operations**: Move collection operations outside view body
2. **Proper ForEach IDs**: Use unique identifiers instead of .self
3. **View Decomposition**: Break large views into smaller components
4. **State Efficiency**: Only update state when UI changes are needed

### Accessibility
1. **Labels**: Provide accessibility labels for all interactive elements
2. **Hints**: Add accessibility hints for complex interactions
3. **Color Independence**: Don't rely solely on color to convey information
4. **Semantic Structure**: Use proper semantic markup and grouping

## 🔮 Future Enhancements

### ✅ Recently Completed
- **String-Based Rule Identification**: ✅ **COMPLETED** - Replaced hardcoded `RuleIdentifier(rawValue:)` calls with direct enum cases
- **UserDefaults Storage**: ✅ **COMPLETED** - Migrated from string arrays to JSON-encoded enum storage for type safety
- **Pattern Detection Methods**: ✅ **COMPLETED** - Updated SwiftSyntaxPatternDetector to use `[RuleIdentifier]` instead of `[String]` parameters
- **Complete Regex Removal**: ✅ **COMPLETED** - Final migration from regex to SwiftSyntax.

### 🔄 In Progress
- **Property Wrapper/String Logic**: Replace remaining hard-wired strings with type-safe enums (see [__string_comparison.md](./__string_comparison.md))

### 📋 Planned Features
- **Enhanced Navigation Detection**: Context-aware nested navigation analysis (see [NestedNavigationDetection_PRD.md](./NestedNavigationDetection_PRD.md))
- **Xcode Extension**: Integrate with Xcode for real-time analysis
- **Custom Rules Engine**: Allow teams to define project-specific rules
- **Performance Profiling**: Detect inefficient view updates and state changes
- **Dependency Graph Visualization**: Visual representation of view relationships
- **Auto-fix Suggestions**: Automatic code generation for common issues
- **CI/CD Integration**: Run as part of automated build processes

## 🧪 Testing

The project includes comprehensive test coverage:
- Unit tests for pattern detection
- Integration tests for analysis pipeline
- UI tests for user interactions
- Example views demonstrating various issues
- SwiftSyntax visitor tests for AST analysis

### Test Categories
- **SwiftUIManagementVisitorTests**: Property wrapper and state pattern tests
- **PerformanceVisitorTests**: Performance anti-pattern detection
- **ArchitectureVisitorTests**: Architectural pattern validation
- **CodeQualityVisitorTests**: Code style and quality checks
- **SecurityVisitorTests**: Security pattern detection
- **AccessibilityVisitorTests**: Accessibility pattern analysis
- **MemoryManagementVisitorTests**: Memory-related issue detection
- **NetworkingVisitorTests**: Networking anti-pattern validation
- **UIVisitorTests**: UI pattern analysis including navigation
- **ViewRelationshipVisitorTests**: View hierarchy mapping
- **SwiftSyntaxPatternDetectorTests**: AST-based pattern detection
- **StateVariableVisitorTests**: State variable extraction and analysis

## 📊 Current Status

### Architecture Improvements
- **SwiftSyntax Migration**: ✅ **COMPLETED** - 100% migrated from regex to SwiftSyntax for core analysis.
- **Type-Safe Detection**: ✅ **COMPLETED** - Enum-based pattern detection fully implemented for rules/categories with RuleIdentifier enum
- **Visitor Pattern**: Comprehensive SwiftSyntax visitor hierarchy for precise analysis
- **Modular Design**: Clear separation between UI and core analysis logic

### Completed Refactoring ✅
- **String-Based Rule Identification**: ✅ **COMPLETED** - Replaced hardcoded `RuleIdentifier(rawValue:)` calls with direct enum cases
- **UserDefaults Storage**: ✅ **COMPLETED** - Migrated from string arrays to JSON-encoded enum storage for type safety
- **Pattern Detection Methods**: ✅ **COMPLETED** - Updated SwiftSyntaxPatternDetector to use `[RuleIdentifier]` instead of `[String]` parameters
- **ProjectLinter Integration**: ✅ **COMPLETED** - Updated analyzeProject methods to use enum-based rule identification

### Ongoing Refactoring
- **Property Wrapper/String Logic**: Property wrapper and view type logic still partly string-based (see [__string_comparison.md](./__string_comparison.md))
- **Performance Optimization**: AST caching and incremental analysis not yet implemented
- **Code Organization**: Several files remain very large and need splitting (see [__refactor.md](./__refactor.md))

### Technical Debt
- **Large File Sizes**: Several files exceed 500-700 lines and need refactoring
- **Mixed Responsibilities**: Some classes combine UI, business logic, and file operations
- **Synchronous Operations**: File and analysis operations need async/await conversion
- **Test Coverage**: Core logic needs more comprehensive integration tests
- **Error Handling**: Inconsistent use of Result types and error propagation

## 🚧 Current Limitations & Roadmap

### ✅ Recently Completed
- **String-Based Rule Identification**: ✅ **COMPLETED** - All hardcoded `RuleIdentifier(rawValue:)` calls replaced with direct enum cases
- **UserDefaults Storage**: ✅ **COMPLETED** - Migrated from string arrays to JSON-encoded enum storage for type safety
- **Pattern Detection Methods**: ✅ **COMPLETED** - Updated SwiftSyntaxPatternDetector to use `[RuleIdentifier]` instead of `[String]` parameters
- **ProjectLinter Integration**: ✅ **COMPLETED** - Updated analyzeProject methods to use enum-based rule identification

### 🔄 Ongoing Work
- **Property Wrapper/String Logic**: Property wrapper, view type, and AST node logic still use string comparisons in many places. See [__string_comparison.md](./__string_comparison.md) for the migration plan.
- **Large Files**: Files like `SwiftUIManagementVisitor.swift`, `SwiftSyntaxPatternDetector.swift`, `ContentView.swift`, and others remain very large and need to be split for maintainability. See [__refactor.md](./__refactor.md) for recommendations.

### 📋 Future Work
- **Async/Await & Performance**: Async/await is only partially implemented. AST caching and incremental analysis are not yet present.
- **Error Handling**: Not all operations use Result types or custom error enums; error propagation is inconsistent.
- **Testing**: While unit test coverage is strong, more integration and performance tests are needed.
- **Documentation**: API documentation and configuration examples are basic and need expansion.

For a detailed roadmap and actionable steps, see [__refactor.md](./__refactor.md).

## 🤝 Contributing

This project demonstrates advanced SwiftUI project analysis techniques. Contributions are welcome for:

### ✅ Recently Completed
- **String-Based Rule Identification**: ✅ **COMPLETED** - All hardcoded `RuleIdentifier(rawValue:)` calls replaced with direct enum cases
- **UserDefaults Storage**: ✅ **COMPLETED** - Migrated from string arrays to JSON-encoded enum storage for type safety
- **Pattern Detection Methods**: ✅ **COMPLETED** - Updated SwiftSyntaxPatternDetector to use `[RuleIdentifier]` instead of `[String]` parameters

### 🔄 Current Priorities
- **Property Wrapper/String Logic**: Replace remaining string comparisons with type-safe enums
- **Large File Refactoring**: Split large files for better maintainability

### 📋 General Contributions
- Enhanced pattern detection
- Additional architectural rules
- Performance optimizations
- UI improvements
- Documentation
- New visitor implementations
- Improving test coverage

## 📄 License

This project is for educational and demonstration purposes. Feel free to use and modify for your own projects.

## 🔗 Related Documentation

- [__string_comparison.md](./__string_comparison.md) - String comparison refactoring strategy
- [__refactor.md](./__refactor.md) - Comprehensive refactoring recommendations
- [NestedNavigationDetection_PRD.md](./NestedNavigationDetection_PRD.md) - Enhanced nested Navigation detection strategy

## 📁 Project Directory Structure (SPM Best Practice)

The project now follows the Swift Package Manager (SPM) best practice layout:

```
SwiftProjectLint/
├── Package.swift
├── Sources/
│   ├── SwiftProjectLint/         # Main app target (UI, CLI, etc.)
│   └── SwiftProjectLintCore/     # Core library target (analysis, detection, etc.)
├── Tests/
│   ├── SwiftProjectLintTests/        # Tests for the main app target
│   └── SwiftProjectLintCoreTests/    # Tests for the core library target
├── Docs/                        # Documentation and design notes
├── Scripts/                     # Utility scripts
├── Output/                      # Build artifacts or generated files
└── ... (other folders)
```

- All source files for `SwiftProjectLintCore` are in `Sources/SwiftProjectLintCore/`.
- All source files for `SwiftProjectLint` are in `Sources/SwiftProjectLint/`.
- All test files are in the corresponding `Tests/<TargetName>Tests/` folders.
- There are no redundant top-level folders; everything is organized under `Sources/` and `Tests/`.

> **Note:** If you are updating from a previous version, make sure to update your Xcode project and `Package.swift` to reference the new paths as shown above.
