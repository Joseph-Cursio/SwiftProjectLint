import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
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
}
