import Foundation
import SwiftParser
import SwiftSyntax

// MARK: - Advanced Analysis Models

/// Represents a hierarchical or navigational relationship between two SwiftUI views detected during analysis.
///
/// `ViewRelationship` models how one view ("parent") is connected to another view ("child") within a SwiftUI codebase,
/// including containment, navigation, modal presentation, or tab relationships. Each instance describes the type of
/// relationship, the names of the parent and child views, and the exact location (file and line number) where the
/// relationship was found in the source code.
///
/// Use this structure to build a view hierarchy, analyze navigation and presentation flows, and detect architectural
/// patterns or anti-patterns in SwiftUI projects.
///
/// - Parameters:
///   - parentView: The name of the view that contains, presents, or navigates to the child view.
///   - childView: The name of the view being contained, presented, or navigated to.
///   - relationshipType: The manner in which the parent and child are connected (e.g., direct child, navigation, sheet, etc.).
///   - lineNumber: The line number in the source file where the relationship is present.
///   - filePath: The file system path of the source file containing the relationship.
///
/// ### Example
/// ```swift
/// let relationship = ViewRelationship(
///     parentView: "RootView",
///     childView: "DetailsView",
///     relationshipType: .navigationDestination,
///     lineNumber: 34,
///     filePath: "/path/to/RootView.swift"
/// )
/// ```
struct ViewRelationship {
    let parentView: String
    let childView: String
    let relationshipType: RelationshipType
    let lineNumber: Int
    let filePath: String
}

enum RelationshipType {
    case directChild
    case navigationDestination
    case sheet
    case fullScreenCover
    case popover
    case alert
    case tabView
}

/// Represents an architectural issue detected during analysis of a SwiftUI codebase.
///
/// `ArchitectureIssue` describes a specific problem, suboptimal pattern, or improvement opportunity found in the architecture of SwiftUI views and their state management. Each instance includes the type and severity of the issue, a human-readable message, the set of affected views, a suggested action to resolve or improve, and the precise source location (file and line number).
///
/// Use this structure to present actionable feedback to developers, enabling them to improve state sharing, data flow consistency, property wrapper usage, and overall project architecture.
///
/// - Parameters:
///   - type: The kind of architecture issue detected (e.g., duplicate state, missing state object, inefficient state sharing, etc.).
///   - severity: The seriousness of the issue (e.g., info, warning, error).
///   - message: A descriptive message explaining the nature of the problem or recommendation.
///   - affectedViews: The list of view names impacted by this issue.
///   - suggestion: An actionable recommendation for resolving the issue or improving architecture.
///   - filePath: The file system path of the source file where the issue was found.
///   - lineNumber: The line number in the source file associated with the issue.
///
/// ### Example
/// ```swift
/// let issue = ArchitectureIssue(
///     type: .duplicateState,
///     severity: .warning,
///     message: "Duplicate state variable 'userSettings' found across related views: RootView, DetailsView",
///     affectedViews: ["RootView", "DetailsView"],
///     suggestion: "Create a shared ObservableObject for 'userSettings' and inject it via .environmentObject() at the root level.",
///     filePath: "/path/to/RootView.swift",
///     lineNumber: 17
/// )
/// ```
struct ArchitectureIssue {
    let type: ArchitectureIssueType
    let severity: IssueSeverity
    let message: String
    let affectedViews: [String]
    let suggestion: String
    let filePath: String
    let lineNumber: Int
}

/// Describes the kind of architectural issue detected during analysis of a SwiftUI codebase.
///
/// `ArchitectureIssueType` enumerates the main categories of state management and architectural problems found in
/// SwiftUI view hierarchies. Each case corresponds to a specific type of anti-pattern or improvement opportunity,
/// helping to classify and prioritize issues for developers.
///
/// - Cases:
///   - `duplicateState`: The same state variable is declared in multiple related views, leading to duplication and potential inconsistency.
///   - `missingStateObject`: A root view managing an observable object is using the `@ObservedObject` property wrapper instead of `@StateObject`, risking improper initialization or lifecycle management.
///   - `inefficientStateSharing`: State is passed inefficiently, such as being manually propagated through many layers, rather than being injected or centralized.
///   - `circularDependency`: The view hierarchy contains circular references, which can lead to data flow problems or runtime issues.
///   - `missingEnvironmentObject`: A state variable that should be injected via `@EnvironmentObject` is either missing or not properly injected, resulting in inconsistent or incomplete data flow.
///   - `inconsistentDataFlow`: State or data is shared between views in an inconsistent or error-prone manner, such as mixing different property wrappers or using ad hoc patterns.
///
/// Use this type to classify detected problems and to guide actionable suggestions for codebase improvement.
enum ArchitectureIssueType {
    case duplicateState
    case missingStateObject
    case inefficientStateSharing
    case circularDependency
    case missingEnvironmentObject
    case inconsistentDataFlow
}

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
    internal var viewRelationships: [ViewRelationship] = []
    internal var stateVariables: [StateVariable] = []
    internal var viewHierarchies: [String: [String]] = [:] // parent -> children
    
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
        issues.append(contentsOf: analyzeStateManagement())
        
        // 3. Detect architectural anti-patterns
        issues.append(contentsOf: detectArchitecturalAntiPatterns())
        
        // 4. Suggest improvements
        issues.append(contentsOf: suggestImprovements())
        
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
    @MainActor internal func buildViewHierarchy(from projectPath: String) {
        let swiftFiles = findSwiftFiles(in: projectPath)
        
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
    @MainActor internal func extractViewRelationships(from filePath: String) -> [ViewRelationship] {
        var relationships: [ViewRelationship] = []
        
        let parentView = extractViewName(from: filePath)
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
    @MainActor internal func extractStateVariables(from filePath: String) -> [StateVariable] {
        var stateVariables: [StateVariable] = []
        
        let sourceFile = Parser.parse(source: (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? "")
        
        let viewName = extractViewName(from: filePath)
        let sourceContents = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
        let visitor = StateVariableVisitor(viewName: viewName, filePath: filePath, sourceContents: sourceContents)
        visitor.walk(sourceFile)
        stateVariables.append(contentsOf: visitor.stateVariables)
        
        return stateVariables
    }
    

    
    /// Extracts the view name from a given Swift file path.
    ///
    /// This method takes a file path string (e.g., "/Users/project/MyView.swift") and returns the base file name
    /// without its extension, which is used as the view's name in internal analysis. For example, given the input
    /// "/path/to/ContentView.swift", the returned view name will be "ContentView".
    ///
    /// - Parameter filePath: The full file system path to a Swift source file.
    /// - Returns: The name of the view, derived from the file name by removing the ".swift" extension.
    internal func extractViewName(from filePath: String) -> String {
        let fileName = (filePath as NSString).lastPathComponent
        return fileName.replacingOccurrences(of: ".swift", with: "")
    }
    
    /// Recursively searches the specified directory for Swift source files.
    ///
    /// This method traverses the directory tree rooted at the given `path`, returning the full file paths of all files
    /// with the `.swift` extension. It uses the file system's enumerator to efficiently locate all Swift files,
    /// regardless of their depth within the directory hierarchy.
    ///
    /// - Parameter path: The root directory path in which to search for Swift files.
    /// - Returns: An array of full file paths to `.swift` files found within the directory and its subdirectories.
    ///
    /// - Note: Hidden files, non-Swift files, and files inside system or build directories are not explicitly excluded
    ///         unless they lack the `.swift` file extension.
    /// - Warning: Symbolic links and circular directory structures may cause redundant file paths or infinite loops,
    ///            depending on the file system's enumerator behavior.
    internal func findSwiftFiles(in path: String) -> [String] {
        let fileManager = FileManager.default
        var swiftFiles: [String] = []
        
        guard let enumerator = fileManager.enumerator(atPath: path) else {
            return swiftFiles
        }
        
        while let filePath = enumerator.nextObject() as? String {
            if filePath.hasSuffix(".swift") {
                swiftFiles.append((path as NSString).appendingPathComponent(filePath))
            }
        }
        
        return swiftFiles
    }
    
    /// Analyzes the extracted state variables to detect patterns and issues related to state management across the SwiftUI codebase.
    ///
    /// This method performs the following checks:
    /// - Identifies duplicate state variable names across views, suggesting potential state sharing improvements.
    /// - Detects duplicate state variables that occur in views which are related (e.g., parent and child), indicating possible inefficient or redundant state allocation.
    /// - For each duplicate state variable found in related views, creates an `ArchitectureIssue` describing the problem, listing the affected views, and providing actionable suggestions for better state management (such as adopting shared `ObservableObject` patterns).
    ///
    /// - Returns: An array of `ArchitectureIssue` objects highlighting detected state management problems and recommendations for improvement.
    internal func analyzeStateManagement() -> [ArchitectureIssue] {
        var issues: [ArchitectureIssue] = []
        
        // Detect duplicate state variables across any views
        let stateNames = stateVariables.map { $0.name }
        let duplicateNames = findDuplicates(in: stateNames)
        
        for duplicateName in duplicateNames {
            let duplicateStates = stateVariables.filter { $0.name == duplicateName }
            
            if duplicateStates.count > 1 {
                let affectedViews = duplicateStates.map { $0.viewName }
                let relatedViews = findRelatedViews(affectedViews)
                
                // Create separate issues for related vs unrelated duplicate state variables
                if !relatedViews.isEmpty {
                    // Related views (parent-child hierarchy)
                    let issue = ArchitectureIssue(
                        type: .duplicateState,
                        severity: .warning,
                        message: """
                        Duplicate state variable '\(duplicateName)' detected in related views.
                        Affected views: \(affectedViews.joined(separator: ", "))
                        Relationships: \(relatedViews.joined(separator: ", "))
                        Occurrences:
                        \(duplicateStates.map { "- \($0.viewName) at \($0.filePath):\($0.lineNumber)" }.joined(separator: "\n"))
                        """,
                        affectedViews: affectedViews,
                        suggestion: generateStateSharingSuggestion(for: duplicateName, views: affectedViews),
                        filePath: duplicateStates[0].filePath,
                        lineNumber: duplicateStates[0].lineNumber
                    )
                    issues.append(issue)
                } else {
                    // Unrelated views (separate views with no hierarchy relationship)
                    let issue = ArchitectureIssue(
                        type: .duplicateState,
                        severity: .info,
                        message: """
                        Duplicate state variable '\(duplicateName)' detected in unrelated views.
                        Affected views: \(affectedViews.joined(separator: ", "))
                        Views are not directly related in hierarchy.
                        Occurrences:
                        \(duplicateStates.map { "- \($0.viewName) at \($0.filePath):\($0.lineNumber)" }.joined(separator: "\n"))
                        """,
                        affectedViews: affectedViews,
                        suggestion: "Consider if these variables represent the same concept and should be shared via a common ObservableObject.",
                        filePath: duplicateStates[0].filePath,
                        lineNumber: duplicateStates[0].lineNumber
                    )
                    issues.append(issue)
                }
            }
        }
        
        return issues
    }
    
    /// Detects architectural anti-patterns related to state management in the analyzed SwiftUI codebase.
    ///
    /// This method examines the previously extracted state variables to identify common SwiftUI architectural issues,
    /// focusing on the misuse of property wrappers in root views. Specifically, it checks for instances where an
    /// `@ObservedObject` property wrapper is used in a root view instead of the recommended `@StateObject`.
    ///
    /// - Returns: An array of `ArchitectureIssue` objects describing each detected anti-pattern, including a warning,
    ///   the affected view(s), file location, and actionable suggestions to correct the issue.
    ///
    /// ### Currently Checked Anti-Patterns
    /// - **Misuse of `@ObservedObject` in root views**: Suggests that root views owning an observable object
    ///   should use `@StateObject` to ensure proper initialization and lifecycle management.
    ///
    /// > Note: This method can be extended in the future to detect additional anti-patterns such as circular dependencies,
    /// > inconsistent state ownership, or improper use of other property wrappers.
    internal func detectArchitecturalAntiPatterns() -> [ArchitectureIssue] {
        var issues: [ArchitectureIssue] = []
        
        // Detect missing @StateObject usage
        for stateVar in stateVariables {
            if stateVar.propertyWrapper == PropertyWrapper.observedObject && isRootView(stateVar.viewName) {
                let issue = ArchitectureIssue(
                    type: .missingStateObject,
                    severity: .warning,
                    message: "Consider using @StateObject instead of @ObservedObject for '\(stateVar.name)' in \(stateVar.viewName)",
                    affectedViews: [stateVar.viewName],
                    suggestion: "Use @StateObject for ObservableObject properties that should be owned by this view.",
                    filePath: stateVar.filePath,
                    lineNumber: stateVar.lineNumber
                )
                issues.append(issue)
            }
        }
        
        return issues
    }
    
    /// Suggests improvements for state management patterns detected in the analyzed SwiftUI codebase.
    ///
    /// This method identifies state variables that are used across multiple views, which may indicate the need for a more efficient or centralized state sharing approach.
    /// Specifically, it suggests using `@EnvironmentObject` for state variables that appear in multiple views, recommending the use of a shared `ObservableObject` injected at the root level of the view hierarchy.
    ///
    /// - Returns: An array of `ArchitectureIssue` objects, each providing an informational suggestion to use `@EnvironmentObject` for widely shared state variables.
    ///
    /// ### When to Use
    /// - When a state variable is duplicated across multiple views, consider centralizing the state using an `ObservableObject` and injecting it via `.environmentObject()` to improve consistency, reduce duplication, and streamline data flow.
    ///
    /// ### Example Output
    /// - Suggestion: "Consider using @EnvironmentObject for 'userSettings' as it's used across multiple views."
    /// - Suggestion: "Create a shared ObservableObject and inject it via .environmentObject() at the root level."
    internal func suggestImprovements() -> [ArchitectureIssue] {
        var issues: [ArchitectureIssue] = []
        
        // Suggest EnvironmentObject for widely shared state
        let sharedStateVars = findWidelySharedState()
        
        for stateVar in sharedStateVars {
            let issue = ArchitectureIssue(
                type: .missingEnvironmentObject,
                severity: .info,
                message: "Consider using @EnvironmentObject for '\(stateVar.name)' as it's used across multiple views",
                affectedViews: [stateVar.viewName],
                suggestion: "Create a shared ObservableObject and inject it via .environmentObject() at the root level.",
                filePath: stateVar.filePath,
                lineNumber: stateVar.lineNumber
            )
            issues.append(issue)
        }
        
        return issues
    }
    
    internal func findDuplicates<T: Hashable>(in array: [T]) -> [T] {
        var seen = Set<T>()
        var duplicates = Set<T>()
        
        for item in array {
            if seen.contains(item) {
                duplicates.insert(item)
            } else {
                seen.insert(item)
            }
        }
        
        return Array(duplicates)
    }
    
    internal func findRelatedViews(_ viewNames: [String]) -> [String] {
        var related: [String] = []
        
        for viewName in viewNames {
            // Check if views are in the same hierarchy
            if let children = viewHierarchies[viewName] {
                related.append(contentsOf: children)
            }
            
            // Check if view is a child of any other view in the list
            for otherView in viewNames {
                if let children = viewHierarchies[otherView], children.contains(viewName) {
                    related.append(viewName)
                }
            }
        }
        
        return Array(Set(related))
    }
    
    internal func isRootView(_ viewName: String) -> Bool {
        // A view is considered root if it's not a child of any other view
        for (_, children) in viewHierarchies {
            if children.contains(viewName) {
                return false
            }
        }
        return true
    }
    
    internal func findWidelySharedState() -> [StateVariable] {
        let stateNames = stateVariables.map { $0.name }
        let duplicateNames = findDuplicates(in: stateNames)
        
        return stateVariables.filter { duplicateNames.contains($0.name) }
    }
    
    internal func generateStateSharingSuggestion(for stateName: String, views: [String]) -> String {
        if views.count == 2 {
            return "Create a shared ObservableObject for '\(stateName)' and pass it from \(views[0]) to \(views[1]) using @ObservedObject."
        } else {
            return "Create a shared ObservableObject for '\(stateName)' and inject it via .environmentObject() at the root level for use across \(views.count) views."
        }
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

// MARK: - SwiftSyntax Visitors



