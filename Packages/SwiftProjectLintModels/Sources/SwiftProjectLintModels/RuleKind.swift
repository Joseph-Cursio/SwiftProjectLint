//
//  RuleKind.swift
//  SwiftProjectLint
//
//  Whether a rule takes a census or reports a defect, for consumers of the
//  JSON report (SwiftStats counts census rules per function and treats every
//  other rule as a defect).
//

/// What a rule's findings are.
public enum RuleKind: String, CaseIterable, Codable, Sendable {
    /// Each finding states a fact about the code, not a claim that something
    /// is wrong: a property-test candidate, an impure closure. Its suggestion,
    /// if any, is optional.
    case census
    /// Each finding claims something is wrong at that place.
    case defect
}

public extension RuleIdentifier {
    /// The rules that take a census. Every other rule reports a defect.
    ///
    /// `CandidateInventory.inventoryRules`, the census rules the text report
    /// collapses for volume, is a subset. `impureClosureInventory` is a census
    /// too, the complement of `pureClosureCandidate`, but it is still listed.
    static let censusRules: Set<RuleIdentifier> = [
        .pureFunctionCandidate,
        .pureClosureCandidate,
        .pureMutatorCandidate,
        .impureClosureInventory
    ]

    /// Whether this rule takes a census or reports a defect.
    var kind: RuleKind {
        Self.censusRules.contains(self) ? .census : .defect
    }

    /// The case name, such as `forceUnwrap`: stable across display-name edits.
    var caseName: String {
        String(describing: self)
    }
}
