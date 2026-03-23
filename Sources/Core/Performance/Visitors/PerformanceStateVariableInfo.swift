import Foundation

/// Information about a state variable for tracking unnecessary updates
struct PerformanceStateVariableInfo {
    let name: String
    let declaredAtLine: Int
    var isUsedInViewBody: Bool
    var isAssigned: Bool
    var assignmentLine: Int?
}
