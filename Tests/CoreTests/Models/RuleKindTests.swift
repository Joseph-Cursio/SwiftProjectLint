@testable import Core
import Foundation
import Testing

/// `kind` and `caseName` are what JSON consumers key on, so they must stay exact.
struct RuleKindTests {
    @Test
    func censusRulesAreExactlyTheFour() {
        let census = RuleIdentifier.allCases.filter { $0.kind == .census }
        let expected: Set<RuleIdentifier> = [
            .pureFunctionCandidate, .pureClosureCandidate, .pureMutatorCandidate, .impureClosureInventory
        ]
        #expect(Set(census) == expected)
    }

    @Test
    func collapsedCandidatesAreCensusRules() {
        #expect(CandidateInventory.inventoryRules.isSubset(of: RuleIdentifier.censusRules))
    }

    @Test
    func caseNamesAreUniqueIdentifiers() {
        let names = RuleIdentifier.allCases.map(\.caseName)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { name in
            name.first?.isLowercase == true && name.allSatisfy { $0.isLetter || $0.isNumber }
        })
        #expect(RuleIdentifier.forceUnwrap.caseName == "forceUnwrap")
    }
}
