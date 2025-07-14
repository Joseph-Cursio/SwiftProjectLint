# Dependency Injection Refactoring Proposal for SwiftProjectLint

## 📋 Executive Summary

This document provides a comprehensive proposal for refactoring the SwiftProjectLint project to implement a robust dependency injection (DI) system. The current codebase previously relied heavily on singletons and direct instantiation, but several protocols have now been created and some files have been refactored for improved modularity and maintainability. This ongoing refactoring will further improve testability, modularity, and overall code quality.

## 🎯 Current State Analysis

### Existing Dependency Management Issues

#### 1. **Singleton Pattern Overuse**
The codebase currently uses several singleton patterns that create tight coupling:

```swift
// Current problematic patterns found in codebase:
PatternVisitorRegistry.shared
SwiftSyntaxPatternRegistry.shared
URLSession.shared
```

**Files affected:**
- `SwiftSyntaxPatternRegistry.swift` (line 25)
- `SwiftSyntaxPatternDetector.swift` (line 151)
- `ProjectLinter.swift` (lines 155, 265)
- `PatternDetectorTests.swift` (line 97)
- `SwiftProjectLintCoreTests.swift` (line 23)

#### 2. **Direct Instantiation**
Multiple classes create dependencies directly without abstraction:

```swift
// Current direct instantiation patterns:
let detector = SwiftSyntaxPatternDetector()
let registry = SwiftSyntaxPatternRegistry.shared
let linter = ProjectLinter()
```

**Files affected:**
- `ContentView.swift` (via SystemComponents)
- `ProjectLinter.swift` (lines 155, 265)
- `PatternDetectorTests.swift` (multiple instances)
- `TestRegistryManager.swift` (lines 18, 58, 72, 80)

#### 3. **Tight Coupling in UI Layer**
The UI layer is tightly coupled to concrete implementations:

```swift
// Current ContentView dependency:
@EnvironmentObject var systemComponents: SystemComponents
```

**Issues:**
- Hard to test in isolation
- Difficult to mock dependencies
- UI logic mixed with business logic

## 🏗️ Proposed Dependency Injection Architecture

### 1. **Core DI Container**

```swift
/// Main dependency injection container for SwiftProjectLint
@MainActor
public class DependencyContainer: ObservableObject {
    
    // MARK: - Singleton Instance
    public static let shared = DependencyContainer()
    
    // MARK: - Core Services
    private var _patternVisitorRegistry: PatternVisitorRegistry?
    private var _swiftSyntaxPatternRegistry: SwiftSyntaxPatternRegistry?
    private var _swiftSyntaxPatternDetector: SwiftSyntaxPatternDetector?
    private var _projectLinter: ProjectLinter?
    private var _fileManager: FileManager?
    private var _urlSession: URLSession?
    
    // MARK: - Configuration
    private var configuration: ContainerConfiguration
    
    // MARK: - Initialization
    private init(configuration: ContainerConfiguration = .default) {
        self.configuration = configuration
    }
    
    // MARK: - Public Interface
    public func configure(with configuration: ContainerConfiguration) {
        self.configuration = configuration
        reset()
    }
    
    public func reset() {
        _patternVisitorRegistry = nil
        _swiftSyntaxPatternRegistry = nil
        _swiftSyntaxPatternDetector = nil
        _projectLinter = nil
        _fileManager = nil
        _urlSession = nil
    }
}

// MARK: - Service Resolution
extension DependencyContainer {
    
    /// Resolves PatternVisitorRegistry instance
    public var patternVisitorRegistry: PatternVisitorRegistry {
        if let existing = _patternVisitorRegistry {
            return existing
        }
        
        let registry = PatternVisitorRegistry()
        _patternVisitorRegistry = registry
        return registry
    }
    
    /// Resolves SwiftSyntaxPatternRegistry instance
    public var swiftSyntaxPatternRegistry: SwiftSyntaxPatternRegistry {
        if let existing = _swiftSyntaxPatternRegistry {
            return existing
        }
        
        let registry = SwiftSyntaxPatternRegistry(visitorRegistry: patternVisitorRegistry)
        if configuration.autoInitializePatterns {
            registry.initialize()
        }
        _swiftSyntaxPatternRegistry = registry
        return registry
    }
    
    /// Resolves SwiftSyntaxPatternDetector instance
    public var swiftSyntaxPatternDetector: SwiftSyntaxPatternDetector {
        if let existing = _swiftSyntaxPatternDetector {
            return existing
        }
        
        let detector = SwiftSyntaxPatternDetector(registry: patternVisitorRegistry)
        _swiftSyntaxPatternDetector = detector
        return detector
    }
    
    /// Resolves ProjectLinter instance
    public var projectLinter: ProjectLinter {
        if let existing = _projectLinter {
            return existing
        }
        
        let linter = ProjectLinter(
            detector: swiftSyntaxPatternDetector,
            fileManager: fileManager
        )
        _projectLinter = linter
        return linter
    }
    
    /// Resolves FileManager instance
    public var fileManager: FileManager {
        if let existing = _fileManager {
            return existing
        }
        
        let manager = configuration.fileManager ?? FileManager.default
        _fileManager = manager
        return manager
    }
    
    /// Resolves URLSession instance
    public var urlSession: URLSession {
        if let existing = _urlSession {
            return existing
        }
        
        let session = configuration.urlSession ?? URLSession.shared
        _urlSession = session
        return session
    }
}
```

### 2. **Configuration System**

```swift
/// Configuration for the dependency injection container
public struct ContainerConfiguration {
    
    // MARK: - Service Configuration
    public let autoInitializePatterns: Bool
    public let enableCaching: Bool
    public let maxCacheSize: Int
    public let fileManager: FileManager?
    public let urlSession: URLSession?
    
    // MARK: - Analysis Configuration
    public let defaultAnalysisCategories: [PatternCategory]
    public let enableParallelProcessing: Bool
    public let maxConcurrentFiles: Int
    
    // MARK: - Initialization
    public init(
        autoInitializePatterns: Bool = true,
        enableCaching: Bool = true,
        maxCacheSize: Int = 100,
        fileManager: FileManager? = nil,
        urlSession: URLSession? = nil,
        defaultAnalysisCategories: [PatternCategory] = PatternCategory.allCases,
        enableParallelProcessing: Bool = true,
        maxConcurrentFiles: Int = 4
    ) {
        self.autoInitializePatterns = autoInitializePatterns
        self.enableCaching = enableCaching
        self.maxCacheSize = maxCacheSize
        self.fileManager = fileManager
        self.urlSession = urlSession
        self.defaultAnalysisCategories = defaultAnalysisCategories
        self.enableParallelProcessing = enableParallelProcessing
        self.maxConcurrentFiles = maxConcurrentFiles
    }
    
    // MARK: - Preset Configurations
    public static let `default` = ContainerConfiguration()
    
    public static let testing = ContainerConfiguration(
        autoInitializePatterns: false,
        enableCaching: false,
        maxCacheSize: 10,
        enableParallelProcessing: false,
        maxConcurrentFiles: 1
    )
    
    public static let production = ContainerConfiguration(
        autoInitializePatterns: true,
        enableCaching: true,
        maxCacheSize: 200,
        enableParallelProcessing: true,
        maxConcurrentFiles: 8
    )
}
```

### 3. **Protocol-Based Abstractions**

```swift
// MARK: - Core Service Protocols






/// Protocol for project analysis operations
public protocol ProjectLinterProtocol {
    func analyzeProject(
        at path: String,
        categories: [PatternCategory]?,
        ruleIdentifiers: [RuleIdentifier]?
    ) async -> [LintIssue]
}

/// Protocol for file system operations
public protocol FileSystemProtocol {
    func fileExists(atPath path: String) -> Bool
    func isReadableFile(atPath path: String) -> Bool
    func contentsOfDirectory(atPath path: String) throws -> [String]
    func subpathsOfDirectory(atPath path: String) throws -> [String]
}

/// Protocol for network operations
public protocol NetworkProtocol {
    func dataTask(
        with url: URL,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask
}
```

### 4. **Updated Service Implementations**

```swift
// MARK: - Updated PatternVisitorRegistry
@MainActor
public class PatternVisitorRegistry: PatternVisitorRegistryProtocol {
    private var patterns: [SyntaxPattern] = []
    private var visitorsByCategory: [PatternCategory: [PatternVisitor.Type]] = [:]
    private let queue = DispatchQueue(label: "PatternVisitorRegistry", attributes: .concurrent)
    
    public init() {}
    
    public func register(pattern: SyntaxPattern) {
        queue.sync(flags: .barrier) {
            self.patterns.append(pattern)
            if self.visitorsByCategory[pattern.category] == nil {
                self.visitorsByCategory[pattern.category] = []
            }
            self.visitorsByCategory[pattern.category]?.append(pattern.visitor)
        }
    }
    
    public func register(patterns: [SyntaxPattern]) {
        queue.sync(flags: .barrier) {
            for pattern in patterns {
                self.patterns.append(pattern)
                if self.visitorsByCategory[pattern.category] == nil {
                    self.visitorsByCategory[pattern.category] = []
                }
                self.visitorsByCategory[pattern.category]?.append(pattern.visitor)
            }
        }
    }
    
    public func getVisitors(for category: PatternCategory) -> [PatternVisitor.Type] {
        return queue.sync {
            return visitorsByCategory[category] ?? []
        }
    }
    
    public func getAllPatterns() -> [SyntaxPattern] {
        return queue.sync {
            return patterns
        }
    }
    
    public func clear() {
        queue.sync(flags: .barrier) {
            patterns.removeAll()
            visitorsByCategory.removeAll()
        }
    }
}

// MARK: - Updated SwiftSyntaxPatternDetector
@MainActor
public class SwiftSyntaxPatternDetector: SwiftSyntaxPatternDetectorProtocol {
    private let registry: PatternVisitorRegistryProtocol
    private var cache: [String: [LintIssue]] = [:]
    private let cacheQueue = DispatchQueue(label: "PatternDetectorCache", attributes: .concurrent)
    
    public init(registry: PatternVisitorRegistryProtocol) {
        self.registry = registry
    }
    
    public func detectPatterns(
        in sourceCode: String,
        filePath: String,
        categories: [PatternCategory]?
    ) async -> [LintIssue] {
        // Check cache first
        let cacheKey = "\(filePath)_\(categories?.description ?? "all")"
        if let cachedIssues = getCachedIssues(for: cacheKey) {
            return cachedIssues
        }
        
        // Perform detection
        let issues = await performDetection(
            sourceCode: sourceCode,
            filePath: filePath,
            categories: categories
        )
        
        // Cache results
        cacheIssues(issues, for: cacheKey)
        return issues
    }
    
    public func clearCache() {
        cacheQueue.sync(flags: .barrier) {
            cache.removeAll()
        }
    }
    
    private func getCachedIssues(for key: String) -> [LintIssue]? {
        return cacheQueue.sync {
            return cache[key]
        }
    }
    
    private func cacheIssues(_ issues: [LintIssue], for key: String) {
        cacheQueue.sync(flags: .barrier) {
            cache[key] = issues
        }
    }
    
    private func performDetection(
        sourceCode: String,
        filePath: String,
        categories: [PatternCategory]?
    ) async -> [LintIssue] {
        // Implementation details...
        return []
    }
}

// MARK: - Updated ProjectLinter
@MainActor
public class ProjectLinter: ProjectLinterProtocol {
    private let detector: SwiftSyntaxPatternDetectorProtocol
    private let fileSystem: FileSystemProtocol
    
    public init(
        detector: SwiftSyntaxPatternDetectorProtocol,
        fileSystem: FileSystemProtocol = FileManager.default
    ) {
        self.detector = detector
        self.fileSystem = fileSystem
    }
    
    public func analyzeProject(
        at path: String,
        categories: [PatternCategory]?,
        ruleIdentifiers: [RuleIdentifier]?
    ) async -> [LintIssue] {
        // Implementation using injected dependencies
        return []
    }
}
```

### 5. **Updated UI Layer with MVVM**

```swift
// MARK: - View Models
@MainActor
public class ProjectAnalysisViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isAnalyzing = false
    @Published var lintIssues: [LintIssue] = []
    @Published var selectedDirectory: String = ""
    @Published var errorMessage: String?
    @Published var analysisProgress: Double = 0.0
    
    // MARK: - Dependencies
    private let projectLinter: ProjectLinterProtocol
    private let patternRegistry: SwiftSyntaxPatternRegistryProtocol
    private let fileSystem: FileSystemProtocol
    
    // MARK: - Initialization
    public init(
        projectLinter: ProjectLinterProtocol,
        patternRegistry: SwiftSyntaxPatternRegistryProtocol,
        fileSystem: FileSystemProtocol = FileManager.default
    ) {
        self.projectLinter = projectLinter
        self.patternRegistry = patternRegistry
        self.fileSystem = fileSystem
    }
    
    // MARK: - Public Methods
    public func analyzeProject() async {
        guard !selectedDirectory.isEmpty else {
            errorMessage = "No project directory selected"
            return
        }
        
        isAnalyzing = true
        errorMessage = nil
        analysisProgress = 0.0
        
        do {
            let issues = await projectLinter.analyzeProject(
                at: selectedDirectory,
                categories: nil,
                ruleIdentifiers: nil
            )
            
            await MainActor.run {
                self.lintIssues = issues
                self.analysisProgress = 1.0
                self.isAnalyzing = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isAnalyzing = false
            }
        }
    }
    
    public func selectDirectory() {
        // Implementation for directory selection
    }
    
    public func getPatternsByCategory() -> [(category: PatternCategory, patterns: [SyntaxPattern])] {
        return PatternCategory.allCases.map { category in
            (category: category, patterns: patternRegistry.getPatterns(for: category))
        }
    }
}

// MARK: - Updated ContentView
struct ContentView: View {
    @StateObject private var viewModel: ProjectAnalysisViewModel
    @State private var showRuleSelector = false
    @State private var enabledRuleNames: Set<RuleIdentifier> = []
    
    init(container: DependencyContainer = .shared) {
        let viewModel = ProjectAnalysisViewModel(
            projectLinter: container.projectLinter,
            patternRegistry: container.swiftSyntaxPatternRegistry
        )
        _viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                headerView
                
                // Action buttons
                actionButtonsView
                
                // Analysis progress
                if viewModel.isAnalyzing {
                    analysisProgressView
                }
                
                // Results
                if !viewModel.lintIssues.isEmpty && !viewModel.isAnalyzing {
                    resultsView
                }
                
                Spacer()
            }
            .frame(minWidth: 600, minHeight: 400)
            .navigationTitle("Project Linter")
            .sheet(isPresented: $showRuleSelector) {
                ruleSelectionView
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
    
    // MARK: - View Components
    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 60))
                .foregroundColor(.blue)
                .accessibilityHidden(true)
            
            Text("Swift Project Linter")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Detect cross-file issues and architectural problems")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 20)
    }
    
    private var actionButtonsView: some View {
        VStack(spacing: 16) {
            Button("Select Rules") {
                showRuleSelector = true
            }
            .buttonStyle(.borderedProminent)
            
            if viewModel.selectedDirectory.isEmpty {
                Button("Run Project Analysis by Selecting a Folder...") {
                    viewModel.selectDirectory()
                }
                .buttonStyle(.bordered)
            } else {
                Button("Analyze \(URL(fileURLWithPath: viewModel.selectedDirectory).lastPathComponent)") {
                    Task {
                        await viewModel.analyzeProject()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var analysisProgressView: some View {
        VStack(spacing: 8) {
            ProgressView(value: viewModel.analysisProgress)
                .scaleEffect(1.2)
            Text("Analyzing project...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 20)
    }
    
    private var resultsView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Analysis Results")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.lintIssues.count) issues found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            LintResultsView(issues: viewModel.lintIssues)
                .frame(maxHeight: 400)
        }
        .padding(.horizontal, 40)
    }
    
    private var ruleSelectionView: some View {
        RuleSelectionDialog(
            allPatternsByCategory: viewModel.getPatternsByCategory().map { category, patterns in
                (category: category, display: category.displayName, patterns: patterns.map { DetectionPattern(from: $0) }, useSwiftSyntax: true)
            },
            enabledRuleNames: $enabledRuleNames,
            onSave: saveEnabledRules
        )
    }
    
    private func saveEnabledRules() {
        // Implementation for saving rules
    }
}
```

## 🔄 Migration Strategy

### Phase 1: Foundation (Week 1)

#### Step 1.1: Create Core DI Infrastructure
1. **Create DependencyContainer.swift**
   - Implement the main container class
   - Add configuration system
   - Create service resolution methods

2. **Create Protocol Abstractions**
   - Define all service protocols
   - Ensure backward compatibility with existing implementations

3. **Update Service Implementations**
   - Modify existing services to conform to protocols
   - Add dependency injection constructors
   - Maintain existing public APIs

#### Step 1.2: Update Core Services
1. **PatternVisitorRegistry**
   ```swift
   // Add protocol conformance
   extension PatternVisitorRegistry: PatternVisitorRegistryProtocol {}
   
   // Update constructor to accept dependencies
   public init() {
       // Existing implementation
   }
   ```

2. **SwiftSyntaxPatternRegistry**
   ```swift
   // Add protocol conformance
   extension SwiftSyntaxPatternRegistry: SwiftSyntaxPatternRegistryProtocol {}
   
   // Update constructor
   public init(visitorRegistry: PatternVisitorRegistryProtocol) {
       self.visitorRegistry = visitorRegistry
   }
   ```

3. **SwiftSyntaxPatternDetector**
   ```swift
   // Add protocol conformance
   extension SwiftSyntaxPatternDetector: SwiftSyntaxPatternDetectorProtocol {}
   
   // Update constructor
   public init(registry: PatternVisitorRegistryProtocol) {
       self.registry = registry
   }
   ```

### Phase 2: UI Layer Refactoring (Week 2)

#### Step 2.1: Create View Models
1. **ProjectAnalysisViewModel**
   - Extract business logic from ContentView
   - Add dependency injection
   - Implement async/await patterns

2. **RuleSelectionViewModel**
   - Extract rule selection logic
   - Add dependency injection
   - Implement state management

#### Step 2.2: Update Views
1. **ContentView**
   - Inject dependencies through constructor
   - Use ViewModel for business logic
   - Remove direct service dependencies

2. **LintResultsView**
   - Make it more modular
   - Add dependency injection where needed

### Phase 3: Testing Infrastructure (Week 3)

#### Step 3.1: Update Test Infrastructure
1. **TestRegistryManager**
   ```swift
   @MainActor
   public class TestRegistryManager {
       private static var testContainer: DependencyContainer?
       
       public static func setupTestContainer() -> DependencyContainer {
           if let existing = testContainer {
               return existing
           }
           
           let container = DependencyContainer()
           container.configure(with: .testing)
           testContainer = container
           return container
       }
       
       public static func resetTestContainer() {
           testContainer?.reset()
           testContainer = nil
       }
   }
   ```

2. **Mock Implementations**
   ```swift
   public class MockPatternVisitorRegistry: PatternVisitorRegistryProtocol {
       public var registeredPatterns: [SyntaxPattern] = []
       
       public func register(pattern: SyntaxPattern) {
           registeredPatterns.append(pattern)
       }
       
       // Implement other protocol methods...
   }
   
   public class MockSwiftSyntaxPatternDetector: SwiftSyntaxPatternDetectorProtocol {
       public var mockIssues: [LintIssue] = []
       
       public func detectPatterns(
           in sourceCode: String,
           filePath: String,
           categories: [PatternCategory]?
       ) async -> [LintIssue] {
           return mockIssues
       }
       
       public func clearCache() {
           // No-op for mocks
       }
   }
   ```

#### Step 3.2: Update Existing Tests
1. **PatternDetectorTests**
   ```swift
   @Test
   static func testPatternDetection() async throws {
       let container = TestRegistryManager.setupTestContainer()
       let detector = container.swiftSyntaxPatternDetector
       
       // Test implementation
   }
   ```

2. **ContentViewTests**
   ```swift
   @Test
   static func testProjectAnalysis() async throws {
       let mockLinter = MockProjectLinter()
       let mockRegistry = MockSwiftSyntaxPatternRegistry()
       
       let viewModel = ProjectAnalysisViewModel(
           projectLinter: mockLinter,
           patternRegistry: mockRegistry
       )
       
       // Test implementation
   }
   ```

### Phase 4: App Integration (Week 4)

#### Step 4.1: Update App Entry Point
1. **SwiftProjectLintApp**
   ```swift
   @main
   struct SwiftProjectLintApp: App {
       @StateObject private var container = DependencyContainer.shared
       
       init() {
           // Configure container based on build configuration
           #if DEBUG
           container.configure(with: .testing)
           #else
           container.configure(with: .production)
           #endif
       }
       
       var body: some Scene {
           WindowGroup {
               ContentView(container: container)
           }
       }
   }
   ```

#### Step 4.2: Remove Legacy Code
1. **Remove SystemComponents**
   - Delete SystemComponents class
   - Update all references to use DependencyContainer

2. **Remove PatternRegistryFactory**
   - Delete PatternRegistryFactory class
   - Update all references to use DependencyContainer

3. **Clean up singletons**
   - Remove `.shared` accessors where possible
   - Update remaining singleton usage to use DI

## 🧪 Testing Strategy

### Unit Testing
```swift
@Suite("DependencyContainer")
struct DependencyContainerTests {
    
    @Test
    static func testServiceResolution() async throws {
        let container = DependencyContainer()
        container.configure(with: .testing)
        
        let registry = container.patternVisitorRegistry
        let detector = container.swiftSyntaxPatternDetector
        
        #expect(registry is PatternVisitorRegistry)
        #expect(detector is SwiftSyntaxPatternDetector)
    }
    
    @Test
    static func testSingletonBehavior() async throws {
        let container1 = DependencyContainer.shared
        let container2 = DependencyContainer.shared
        
        #expect(container1 === container2)
    }
    
    @Test
    static func testConfigurationOverride() async throws {
        let container = DependencyContainer()
        container.configure(with: .testing)
        
        let registry = container.swiftSyntaxPatternRegistry
        // Verify testing configuration is applied
    }
}

@Suite("ProjectAnalysisViewModel")
struct ProjectAnalysisViewModelTests {
    
    @Test
    static func testProjectAnalysis() async throws {
        let mockLinter = MockProjectLinter()
        let mockRegistry = MockSwiftSyntaxPatternRegistry()
        
        let viewModel = ProjectAnalysisViewModel(
            projectLinter: mockLinter,
            patternRegistry: mockRegistry
        )
        
        viewModel.selectedDirectory = "/test/path"
        
        await viewModel.analyzeProject()
        
        #expect(!viewModel.isAnalyzing)
        #expect(viewModel.errorMessage == nil)
    }
    
    @Test
    static func testErrorHandling() async throws {
        let mockLinter = MockProjectLinter()
        mockLinter.shouldThrowError = true
        
        let viewModel = ProjectAnalysisViewModel(
            projectLinter: mockLinter,
            patternRegistry: MockSwiftSyntaxPatternRegistry()
        )
        
        viewModel.selectedDirectory = "/test/path"
        
        await viewModel.analyzeProject()
        
        #expect(viewModel.errorMessage != nil)
    }
}
```

### Integration Testing
```swift
@Suite("DependencyInjectionIntegration")
struct DependencyInjectionIntegrationTests {
    
    @Test
    static func testFullAnalysisPipeline() async throws {
        let container = DependencyContainer()
        container.configure(with: .testing)
        
        let viewModel = ProjectAnalysisViewModel(
            projectLinter: container.projectLinter,
            patternRegistry: container.swiftSyntaxPatternRegistry
        )
        
        // Test complete analysis flow
    }
    
    @Test
    static func testConfigurationPresets() async throws {
        // Test production configuration
        let productionContainer = DependencyContainer()
        productionContainer.configure(with: .production)
        
        // Test testing configuration
        let testingContainer = DependencyContainer()
        testingContainer.configure(with: .testing)
        
        // Verify different behaviors
    }
}
```

## 📊 Benefits and Impact

### Immediate Benefits
1. **Improved Testability**
   - Easy mocking of dependencies
   - Isolated unit testing
   - Better test coverage

2. **Reduced Coupling**
   - Loose coupling between components
   - Easier to modify individual parts
   - Better separation of concerns

3. **Enhanced Maintainability**
   - Clear dependency relationships
   - Easier to understand code flow
   - Simplified debugging

### Long-term Benefits
1. **Scalability**
   - Easy to add new services
   - Simple to extend functionality
   - Better performance optimization

2. **Flexibility**
   - Easy to swap implementations
   - Configuration-driven behavior
   - Environment-specific setups

3. **Code Quality**
   - Better architecture patterns
   - Consistent dependency management
   - Improved code organization

## 🚨 Risks and Mitigation

### Potential Risks
1. **Breaking Changes**
   - Risk: Existing code may break during migration
   - Mitigation: Incremental migration with backward compatibility

2. **Performance Impact**
   - Risk: DI container overhead
   - Mitigation: Lazy initialization and caching

3. **Complexity Increase**
   - Risk: More complex setup for simple cases
   - Mitigation: Sensible defaults and helper methods

### Mitigation Strategies
1. **Backward Compatibility**
   - Maintain existing public APIs
   - Gradual deprecation of old patterns
   - Clear migration documentation

2. **Performance Optimization**
   - Lazy service resolution
   - Intelligent caching
   - Minimal overhead design

3. **Documentation and Training**
   - Comprehensive documentation
   - Code examples and patterns
   - Team training sessions

## 📅 Implementation Timeline

### Week 1: Foundation
- [x] Create service protocols (several protocols have already been created)
- [x] Refactor some files for size and modularity
- [ ] Create DependencyContainer
- [ ] Update core services to use protocols and DI
- [ ] Basic unit tests

### Week 2: UI Layer
- [ ] Create ViewModels
- [ ] Update ContentView
- [ ] Update other views
- [ ] UI integration tests

### Week 3: Testing
- [ ] Update test infrastructure
- [ ] Create mock implementations
- [ ] Update existing tests
- [ ] Integration tests

### Week 4: Integration
- [ ] Update app entry point
- [ ] Remove legacy code
- [ ] Performance testing
- [ ] Documentation

## 🎯 Success Metrics

### Technical Metrics
1. **Test Coverage**: Increase to >90%
2. **Build Time**: No significant increase
3. **Runtime Performance**: <5% overhead
4. **Code Complexity**: Reduced cyclomatic complexity

### Quality Metrics
1. **Bug Reduction**: 50% fewer dependency-related bugs
2. **Development Speed**: 25% faster feature development
3. **Code Reviews**: 40% faster review process
4. **Onboarding**: 60% faster new developer onboarding

## 📝 Conclusion

This dependency injection refactoring proposal provides a comprehensive roadmap for improving the SwiftProjectLint project's architecture. The proposed changes will significantly enhance testability, maintainability, and overall code quality while maintaining backward compatibility and minimizing disruption to existing functionality.

The phased approach ensures a smooth transition with minimal risk, while the comprehensive testing strategy guarantees that the refactoring doesn't introduce regressions. The long-term benefits of this refactoring will make the codebase more scalable, flexible, and easier to maintain as the project grows.

## 🔗 Related Documents

- [Refactoring Ideas Overview](../__refactoring_ideas.md)
- [MVVM Architecture Proposal](./mvvm_architecture_proposal.md)
- [Testing Strategy Document](./testing_strategy.md)
- [Performance Optimization Plan](./performance_optimization_plan.md) 

## ✅ Actionable To-Do Checklist for Dependency Injection Refactor

Follow these steps to complete the DI refactor. Check off each item as you go:

### 1. Core Infrastructure
- [ ] **Create `DependencyContainer.swift`** in `SwiftProjectLintCore/SwiftProjectLintCore/`.
    - Implement the main DI container as described in the proposal.
    - Add configuration system and service resolution methods.
- [ ] **Update `ContainerConfiguration`** struct if not already present.
    - Ensure it supports all configuration options needed for your services.

### 2. Protocol Adoption & Service Refactoring
- [ ] **Ensure all core services conform to their protocols:**
    - `PatternVisitorRegistry` → `PatternVisitorRegistryProtocol`
    - `SwiftSyntaxPatternRegistry` → `SwiftSyntaxPatternRegistryProtocol`
    - `SwiftSyntaxPatternDetector` → `SwiftSyntaxPatternDetectorProtocol`
    - `ProjectLinter` → `ProjectLinterProtocol`
    - `FileManager`/custom → `FileSystemProtocol`
    - `URLSession`/custom → `NetworkProtocol`
- [ ] **Update constructors to accept protocol types** (not concrete types) for dependencies.
- [ ] **Remove `.shared` singleton usages** in all files (e.g., `PatternVisitorRegistry.shared`).
    - Replace with `DependencyContainer.shared.patternVisitorRegistry` or injected instance.
- [ ] **Refactor direct instantiations** (e.g., `let detector = SwiftSyntaxPatternDetector()`) to use DI.

### 3. UI Layer Refactor
- [ ] **Create/Update ViewModels** (e.g., `ProjectAnalysisViewModel`, `RuleSelectionViewModel`).
    - Inject dependencies via initializers.
    - Move business logic out of views.
- [ ] **Update `ContentView` and other views** to use ViewModels and DI.
    - Pass dependencies via constructor or environment.
    - Remove direct dependency on concrete services.

### 4. Test Infrastructure
- [ ] **Update/Create `TestRegistryManager`** for test DI setup.
- [ ] **Create mock implementations** for all protocols as needed for tests.
- [ ] **Update tests** to use mocks and DI container.

### 5. App Integration & Cleanup
- [ ] **Update `SwiftProjectLintApp` entry point** to configure the DI container.
- [ ] **Remove legacy code:**
    - Delete `SystemComponents` and update all references.
    - Delete `PatternRegistryFactory` and update all references.
    - Remove `.shared` accessors where possible.
- [ ] **Document any new patterns or helpers** for future contributors.

---

**Tip:** Work through the checklist sequentially, committing after each major step. Run tests frequently to catch regressions early.

If you need to reference the original proposal for code snippets or architecture diagrams, see the sections above. 
