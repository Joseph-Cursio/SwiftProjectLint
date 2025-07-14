/// Represents the hierarchical relationship and structure of a SwiftUI view within a project.
///
/// `ViewHierarchy` contains information about a specific view, including its name, its parent view (if any),
/// its direct child views, and a list of state variables declared within that view. This structure is useful for
/// analyzing and visualizing the component relationships in SwiftUI projects, as well as for detecting patterns and potential
/// issues related to state management and view composition.
///
/// - Parameters:
///   - viewName: The name of the SwiftUI view (typically the struct name).
///   - parentView: The name of the parent view, if one exists; otherwise `nil`.
///   - childViews: An array of names of direct child views included in this view's body.
///   - stateVariables: A list of `StateVariable` instances declared within this view.
///
/// - SeeAlso: `StateVariable`
struct ViewHierarchy {
    let viewName: String
    let parentView: String?
    let childViews: [String]
    let stateVariables: [StateVariable]
}