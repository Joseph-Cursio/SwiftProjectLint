import Foundation

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
///   - relationshipType: The manner in which the parent and child are connected
///     (e.g., direct child, navigation, sheet, etc.).
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
public struct ViewRelationship: Sendable {
    public let parentView: String
    public let childView: String
    public let relationshipType: RelationshipType
    public let lineNumber: Int
    public let filePath: String
    
    public init(
        parentView: String,
        childView: String,
        relationshipType: RelationshipType,
        lineNumber: Int,
        filePath: String
    ) {
        self.parentView = parentView
        self.childView = childView
        self.relationshipType = relationshipType
        self.lineNumber = lineNumber
        self.filePath = filePath
    }
}

public enum RelationshipType: Sendable {
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
/// `ArchitectureIssue` describes a specific problem, suboptimal pattern, or improvement opportunity found in the
/// architecture of SwiftUI views and their state management. Each instance includes the type and severity of the issue,
/// a human-readable message, the set of affected views, a suggested action to resolve or improve, and the precise
/// source location (file and line number).
///
/// Use this structure to present actionable feedback to developers, enabling them to improve state sharing, data flow
/// consistency, property wrapper usage, and overall project architecture.
///
/// - Parameters:
///   - type: The kind of architecture issue detected
///     (e.g., duplicate state, missing state object, inefficient state sharing, etc.).
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
public struct ArchitectureIssue {
    public let type: ArchitectureIssueType
    public let severity: IssueSeverity
    public let message: String
    public let affectedViews: [String]
    public let suggestion: String
    public let filePath: String
    public let lineNumber: Int
    
    public init(
        type: ArchitectureIssueType,
        severity: IssueSeverity,
        message: String,
        affectedViews: [String],
        suggestion: String,
        filePath: String,
        lineNumber: Int
    ) {
        self.type = type
        self.severity = severity
        self.message = message
        self.affectedViews = affectedViews
        self.suggestion = suggestion
        self.filePath = filePath
        self.lineNumber = lineNumber
    }
}

/// Describes the kind of architectural issue detected during analysis of a SwiftUI codebase.
///
/// `ArchitectureIssueType` enumerates the main categories of state management and architectural problems found in
/// SwiftUI view hierarchies. Each case corresponds to a specific type of anti-pattern or improvement opportunity,
/// helping to classify and prioritize issues for developers.
///
/// - Cases:
///   - `duplicateState`: The same state variable is declared in multiple related views, leading to duplication and
///     potential inconsistency.
///   - `missingStateObject`: A root view managing an observable object is using the `@ObservedObject` property wrapper
///     instead of `@StateObject`, risking improper initialization or lifecycle management.
///   - `inefficientStateSharing`: State is passed inefficiently, such as being manually propagated through many layers,
///     rather than being injected or centralized.
///   - `circularDependency`: The view hierarchy contains circular references, which can lead to data flow problems or
///     runtime issues.
///   - `missingEnvironmentObject`: A state variable that should be injected via `@EnvironmentObject` is either missing
///     or not properly injected, resulting in inconsistent or incomplete data flow.
///   - `inconsistentDataFlow`: State or data is shared between views in an inconsistent or error-prone manner, such as
///     mixing different property wrappers or using ad hoc patterns.
///
/// Use this type to classify detected problems and to guide actionable suggestions for codebase improvement.
public enum ArchitectureIssueType {
    case duplicateState
    case missingStateObject
    case inefficientStateSharing
    case circularDependency
    case missingEnvironmentObject
    case inconsistentDataFlow
    case directInstantiation
} 
