import Foundation

/// Detector responsible for identifying architectural anti-patterns in SwiftUI codebases.
///
/// This class provides methods to detect common SwiftUI architectural issues such as
/// misuse of property wrappers, missing state objects, and other anti-patterns.
public class ArchitectureIssueDetector {

    /// Detects architectural anti-patterns related to state management in the analyzed SwiftUI codebase.
    ///
    /// This method examines the previously extracted state variables to identify common SwiftUI architectural issues,
    /// focusing on the misuse of property wrappers in root views. Specifically, it checks for instances where an
    /// `@ObservedObject` property wrapper is used in a root view instead of the recommended `@StateObject`.
    ///
    /// - Parameters:
    ///   - stateVariables: Array of state variables to analyze
    ///   - viewHierarchies: Dictionary mapping parent views to their child views
    /// - Returns: An array of `ArchitectureIssue` objects describing each detected anti-pattern, including a warning,
    ///   the affected view(s), file location, and actionable suggestions to correct the issue.
    ///
    /// ### Currently Checked Anti-Patterns
    /// - **Misuse of `@ObservedObject` in root views**: Suggests that root views owning an observable object
    ///   should use `@StateObject` to ensure proper initialization and lifecycle management.
    ///
    /// > Note: This method can be extended in the future to detect additional anti-patterns such as circular dependencies,
    /// > inconsistent state ownership, or improper use of other property wrappers.
    public static func detectArchitecturalAntiPatterns(stateVariables: [StateVariable], viewHierarchies: [String: [String]]) -> [ArchitectureIssue] {
        var issues: [ArchitectureIssue] = []

        // Detect missing @StateObject usage
        for stateVar in stateVariables {
            if stateVar.propertyWrapper == PropertyWrapper.observedObject &&
               isRootView(stateVar.viewName, in: viewHierarchies) {
                let issue = ArchitectureIssue(
                    type: .missingStateObject,
                    severity: .warning,
                    message: "Consider using @StateObject instead of @ObservedObject for '\(stateVar.name)' " +
                             "in \(stateVar.viewName)",
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

    // MARK: - Private Helper Methods

    private static func isRootView(_ viewName: String, in viewHierarchies: [String: [String]]) -> Bool {
        // A view is considered root if it's not a child of any other view
        for (_, children) in viewHierarchies where children.contains(viewName) {
            return false
        }
        return true
    }
}
