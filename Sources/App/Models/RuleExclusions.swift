/// Per-rule path exclusion flags for the GUI.
struct RuleExclusions: Codable, Equatable, Sendable {
    var excludeTests: Bool = false
    var excludeViews: Bool = false
}
