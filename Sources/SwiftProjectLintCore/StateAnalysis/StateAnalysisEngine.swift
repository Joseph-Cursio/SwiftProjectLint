import Foundation

/// Engine responsible for analyzing state management patterns in SwiftUI codebases.
///
/// This class provides methods to detect duplicate state variables, analyze state sharing patterns,
/// and generate suggestions for improving state management across SwiftUI views.
public class StateAnalysisEngine {

    /// Analyzes the extracted state variables to detect patterns and issues related to state management across the SwiftUI codebase.
    ///
    /// This method performs the following checks:
    /// - Identifies duplicate state variable names across views, suggesting potential state sharing improvements.
    /// - Detects duplicate state variables that occur in views which are related (e.g., parent and child),
    ///   indicating possible inefficient or redundant state allocation.
    /// - For each duplicate state variable found in related views, creates an `ArchitectureIssue` describing the problem,
    ///   listing the affected views, and providing actionable suggestions for better state management (such as adopting shared
    ///   `ObservableObject` patterns).
    ///
    /// - Parameters:
    ///   - stateVariables: Array of state variables to analyze
    ///   - viewHierarchies: Dictionary mapping parent views to their child views
    /// - Returns: An array of `ArchitectureIssue` objects highlighting detected state management problems and recommendations
    ///            for improvement.
    public static func analyzeStateManagement(
        stateVariables: [StateVariable],
        viewHierarchies: [String: [String]]
    ) -> [ArchitectureIssue] {
        var issues: [ArchitectureIssue] = []

        // Detect duplicate state variables across any views
        let stateNames = stateVariables.map { $0.name }
        let duplicateNames = findDuplicates(in: stateNames)

        for duplicateName in duplicateNames {
            let duplicateStates = stateVariables.filter { $0.name == duplicateName }

            if duplicateStates.count > 1 {
                let affectedViews = duplicateStates.map { $0.viewName }
                let relatedViews = findRelatedViews(affectedViews, in: viewHierarchies)

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
                        \(duplicateStates.map {
                            "- \($0.viewName) at \($0.filePath):\($0.lineNumber)"
                        }.joined(separator: "\n"))
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
                        \(duplicateStates.map {
                            "- \($0.viewName) at \($0.filePath):\($0.lineNumber)"
                        }.joined(separator: "\n"))
                        """,
                        affectedViews: affectedViews,
                        suggestion: """
                        Consider if these variables represent the same concept and should be shared via a common ObservableObject.
                        """,
                        filePath: duplicateStates[0].filePath,
                        lineNumber: duplicateStates[0].lineNumber
                    )
                    issues.append(issue)
                }
            }
        }

        return issues
    }

    /// Suggests improvements for state management patterns detected in the analyzed SwiftUI codebase.
    ///
    /// This method identifies state variables that are used across multiple views, which may indicate the need for a more
    /// efficient or centralized state sharing approach.
    /// Specifically, it suggests using `@EnvironmentObject` for state variables that appear in multiple views, recommending
    /// the use of a shared `ObservableObject` injected at the root level of the view hierarchy.
    ///
    /// - Parameters:
    ///   - stateVariables: Array of state variables to analyze
    /// - Returns: An array of `ArchitectureIssue` objects, each providing an informational suggestion to use
    ///            `@EnvironmentObject` for widely shared state variables.
    ///
    /// ### When to Use
    /// - When a state variable is duplicated across multiple views, consider centralizing the state using an
    ///   `ObservableObject` and injecting it via `.environmentObject()` to improve consistency, reduce duplication, and streamline data flow.
    ///
    /// ### Example Output
    /// - Suggestion: "Consider using @EnvironmentObject for 'userSettings' as it's used across multiple views."
    /// - Suggestion: "Create a shared ObservableObject and inject it via .environmentObject() at the root level."
    public static func suggestImprovements(stateVariables: [StateVariable]) -> [ArchitectureIssue] {
        var issues: [ArchitectureIssue] = []

        // Suggest EnvironmentObject for widely shared state
        let sharedStateVars = findWidelySharedState(stateVariables: stateVariables)

        for stateVar in sharedStateVars {
            let issue = ArchitectureIssue(
                type: .missingEnvironmentObject,
                severity: .info,
                message: "Consider using @EnvironmentObject for '\(stateVar.name)' as it's used across multiple views",
                affectedViews: [stateVar.viewName],
                suggestion: """
                Create a shared ObservableObject and inject it via .environmentObject() at the root level.
                """,
                filePath: stateVar.filePath,
                lineNumber: stateVar.lineNumber
            )
            issues.append(issue)
        }

        return issues
    }

    // MARK: - Private Helper Methods

    private static func findDuplicates<T: Hashable>(in array: [T]) -> [T] {
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

    private static func findRelatedViews(_ viewNames: [String], in viewHierarchies: [String: [String]]) -> [String] {
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

    private static func findWidelySharedState(stateVariables: [StateVariable]) -> [StateVariable] {
        let stateNames = stateVariables.map { $0.name }
        let duplicateNames = findDuplicates(in: stateNames)

        return stateVariables.filter { duplicateNames.contains($0.name) }
    }

    private static func generateStateSharingSuggestion(for stateName: String, views: [String]) -> String {
        if views.count == 2 {
            return "Create a shared ObservableObject for '\(stateName)' and pass it from \(views[0]) to \(views[1]) using @ObservedObject."
        } else {
            return "Create a shared ObservableObject for '\(stateName)' and inject it via .environmentObject() at the root level " +
                "for use across \(views.count) views."
        }
    }
}

