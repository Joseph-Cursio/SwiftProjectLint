import Foundation
import SwiftParser
import SwiftSyntax

// MARK: - Advanced Analyzer

/// `AdvancedAnalyzer` is responsible for performing in-depth architectural analysis of a SwiftUI codebase.
/// 
/// This analyzer scans all Swift source files within a project directory to build a hierarchy of views and
/// identify both state management patterns and potential architectural issues or anti-patterns. Its main goals are:
///
/// - To discover relationships between views (such as navigation, modal presentation, and containment).
/// - To extract and analyze property wrappers used for state management (e.g., `@State`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject`).
/// - To detect architectural problems, such as duplicate state variables, misuse of property wrappers,
///   missing environment objects, inefficient or inconsistent data flow, and circular dependencies.
/// - To generate actionable suggestions for improving state sharing and overall architecture.
///
/// ### Usage
/// 1. Create an `AdvancedAnalyzer` instance.
/// 2. Call `analyzeArchitecture(projectPath:)` with the file system path of your Swift project.
/// 3. Receive a list of detected `ArchitectureIssue` items, each describing a potential problem or improvement.
///
/// ### Example
/// ```swift
/// let analyzer = AdvancedAnalyzer()
/// let issues = analyzer.analyzeArchitecture(projectPath: "/path/to/project")
/// issues.forEach { print($0) }
/// ```
///
/// ### Implementation Details
/// - The analyzer traverses the project directory recursively to find `.swift` files.
/// - It uses regular expressions to extract view instantiations and property wrapper declarations from code lines.
/// - Builds an internal representation of the view hierarchy and state variable usage.
/// - Applies heuristics to identify duplicate state, misuse of property wrappers, and recommends improved patterns (like `@EnvironmentObject` for widely shared state).
///
/// ### Detected Issue Types
/// - Duplicate state variables across related views
/// - Missing `@StateObject` usage for observable objects in root views
/// - Inefficient state sharing across many views
/// - Circular dependencies in the view hierarchy
/// - Inconsistent data flow or missing environment objects
///
/// ### Thread Safety
/// - `AdvancedAnalyzer` is not thread-safe and should be used from a single thread at a time.
///
/// ### Limitations
/// - Analysis is based on static code scanning and regular expressions, which may miss certain dynamic patterns.
/// - Only `.swift` files are analyzed; generated or external code is ignored.
///
class AdvancedAnalyzer {
    private var viewRelationships: [ViewRelationship] = []
    private var stateVariables: [StateVariable] = []
    private var viewHierarchies: [String: [String]] = [:] // parent -> children
    
    /// Performs an advanced architectural analysis of a SwiftUI codebase located at the specified project path.
    ///
    /// This method initiates a comprehensive static analysis of the project's Swift source files to uncover view hierarchies, analyze state management patterns, and detect architectural issues or anti-patterns. It is intended to help developers improve the maintainability, structure, and data flow of their SwiftUI applications.
    ///
    /// **Core Analysis Steps:**
    /// 1. **View Hierarchy Construction:** Recursively scans all `.swift` files in the project directory, extracting relationships between views (including navigation links, presentations, and direct containment) and building a hierarchical map of the view structure.
    /// 2. **State Management Analysis:** Detects and records state variable declarations using SwiftUI property wrappers (such as `@State`, `@StateObject`, `@ObservedObject`, and `@EnvironmentObject`), identifying usage patterns across the project.
    /// 3. **Architectural Issue Detection:** Applies heuristics to find anti-patterns and potential problems in the codebase, such as duplicate state variables across related views, misuse of property wrappers (e.g., `@ObservedObject` in root views), inefficient state sharing, and missing or inconsistent environment objects.
    /// 4. **Actionable Suggestions:** Generates recommendations for resolving identified issues, including the adoption of shared `ObservableObject`s, proper use of `@StateObject`, and leveraging `.environmentObject()` for widely used state.
    ///
    /// - Parameter projectPath: The root file system path of the SwiftUI project to analyze.
    /// - Returns: An array of `ArchitectureIssue` objects, each describing a detected problem, the affected views and source locations, and recommended actions for improvement.
    ///
    /// ### Example
    /// ```
    /// let analyzer = AdvancedAnalyzer()
    /// let issues = analyzer.analyzeArchitecture(projectPath: "/path/to/project")
    /// issues.forEach { print($0) }
    /// ```
    ///
    /// - Note: The analysis is static and based on regular expressions; dynamic or non-standard code patterns may not be fully detected.
    /// - Warning: This method is not thread-safe; use from a single thread at a time.
    @MainActor func analyzeArchitecture(projectPath: String) -> [ArchitectureIssue] {
        var issues: [ArchitectureIssue] = []
        
        // 1. Build view hierarchy
        buildViewHierarchy(from: projectPath)
        
        // 2. Analyze state management patterns
        issues.append(contentsOf: StateAnalysisEngine.analyzeStateManagement(stateVariables: stateVariables, viewHierarchies: viewHierarchies))
        
        // 3. Detect architectural anti-patterns
        issues.append(contentsOf: ArchitectureIssueDetector.detectArchitecturalAntiPatterns(stateVariables: stateVariables, viewHierarchies: viewHierarchies))
        
        // 4. Suggest improvements
        issues.append(contentsOf: StateAnalysisEngine.suggestImprovements(stateVariables: stateVariables))
        
        return issues
    }
    
    /// Builds the internal representation of the view hierarchy and extracts state variables from the Swift source files within the given project directory.
    ///
    /// - Parameter projectPath: The file system path to the root of the Swift project to be analyzed.
    ///
    /// This method performs the following steps:
    /// 1. Recursively finds all `.swift` files within the specified project directory.
    /// 2. Parses each file using SwiftSyntax to extract relationships between views (e.g., direct child, navigation, modal presentation) and state variable declarations.
    /// 3. For every view relationship detected, constructs a `ViewRelationship` object representing the parent and child views, the type of relationship, and the file location.
    /// 4. For each state variable declaration found, constructs a `StateVariable` object containing its name, type, property wrapper, associated view, file path, and line number.
    /// 5. Builds a mapping of parent views to their child views, forming a hierarchical structure of the views in the project.
    ///
    /// The results are stored internally in the analyzer for use in further architectural analysis and issue detection.
    @MainActor private func buildViewHierarchy(from projectPath: String) {
        let swiftFiles = FileAnalysisUtils.findSwiftFiles(in: projectPath)
        
        for filePath in swiftFiles {
            // Extract view relationships using SwiftSyntax
            let relationships = extractViewRelationships(from: filePath)
            viewRelationships.append(contentsOf: relationships)
            
            // Extract state variables using SwiftSyntax
            let stateVars = extractStateVariables(from: filePath)
            stateVariables.append(contentsOf: stateVars)
        }
        
        // Build hierarchy map
        for relationship in viewRelationships {
            if viewHierarchies[relationship.parentView] == nil {
                viewHierarchies[relationship.parentView] = []
            }
            viewHierarchies[relationship.parentView]?.append(relationship.childView)
        }
    }
    
    /// Extracts view relationships from a Swift source file using SwiftSyntax parsing.
    ///
    /// This method parses the entire Swift file to detect view instantiation patterns and relationships
    /// such as direct child views, navigation destinations, sheet and full screen cover presentations.
    /// It uses SwiftSyntax to accurately parse Swift code and identify view relationships.
    ///
    /// - Parameters:
    ///   - filePath: The full file path of the Swift file to analyze.
    /// - Returns: An array of `ViewRelationship` instances representing all relationships found in the file.
    ///
    /// The function detects the following patterns:
    /// - Direct child view instantiation (e.g., `SomeView()`)
    /// - `NavigationLink` destination views (e.g., `NavigationLink(destination: SomeView())`)
    /// - Sheet presentation (e.g., `.sheet(content: { SomeView() })`)
    /// - Full screen cover presentation (e.g., `.fullScreenCover(content: { SomeView() })`)
    @MainActor private func extractViewRelationships(from filePath: String) -> [ViewRelationship] {
        var relationships: [ViewRelationship] = []
        
        let parentView = FileAnalysisUtils.extractSwiftBasename(from: filePath)
        let sourceContents = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
        let sourceFile = Parser.parse(source: sourceContents)
        let sourceLocationConverter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
        let visitor = ViewRelationshipVisitor(parentView: parentView, filePath: filePath, sourceContents: sourceContents, sourceLocationConverter: sourceLocationConverter)
        visitor.walk(sourceFile)
        relationships.append(contentsOf: visitor.relationships)
        
        return relationships
    }
    
    /// Extracts state variables from a Swift source file using SwiftSyntax parsing.
    ///
    /// This method parses the entire Swift file to detect state property declarations
    /// utilizing common SwiftUI property wrappers: `@State`, `@StateObject`, `@ObservedObject`, and `@EnvironmentObject`.
    ///
    /// - Parameters:
    ///   - filePath: The full file path of the Swift file to analyze.
    /// - Returns: An array of `StateVariable` instances representing all state variables found in the file.
    ///
    /// The returned `StateVariable` instances include the variable's name, type, property wrapper, the associated view name,
    /// as well as the file path and line number where they were found.
    @MainActor private func extractStateVariables(from filePath: String) -> [StateVariable] {
        var stateVariables: [StateVariable] = []
        
        let sourceFile = Parser.parse(source: (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? "")
        
        let viewName = FileAnalysisUtils.extractSwiftBasename(from: filePath)
        let sourceContents = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
        let visitor = StateVariableVisitor(viewName: viewName, filePath: filePath, sourceContents: sourceContents)
        visitor.walk(sourceFile)
        stateVariables.append(contentsOf: visitor.stateVariables)
        
        return stateVariables
    }
    

    

    

    

    

    

    
    // Public: Get the relationship type between two views, if any
    public func relationshipType(between parent: String, and child: String) -> RelationshipType? {
        return viewRelationships.first(where: { $0.parentView == parent && $0.childView == child })?.relationshipType
    }
    
    // Public: Get the full ViewRelationship between two views, if any
    public func viewRelationship(between parent: String, and child: String) -> ViewRelationship? {
        return viewRelationships.first(where: { $0.parentView == parent && $0.childView == child })
    }
}



