@testable import Core
import Testing

/// **The purity gate is only as good as the declarations it is derived from.**
///
/// A visitor that reads the package purity says so by conforming to `PackagePurityConsumer`, naming
/// the surfaces it reads. Which visitors declare what is a reviewed list: a change to it is a change
/// to what a run narrowed to those rules builds.
@Suite("The purity gate is derived from the visitors' declarations")
struct PurityGateDeclarationTests {

    // MARK: - The declarations

    static let registered = PatternRegistryFactory.createConfiguredSystem().visitorRegistry.getAllPatterns()

    static let ruleNames: [RuleIdentifier] = Set(registered.map(\.name)).sorted { $0.rawValue < $1.rawValue }

    /// The reviewed list. A change here is a change to what narrow runs cost, and gets reviewed.
    static let expectedDeclarations: [RuleIdentifier: PackagePurityInputs] = [
        .pureFunctionCandidate: [.oracle, .cleanInstanceMethods, .impurePackageFunctions],
        .pureClosureCandidate: [.oracle],
        .impureClosureInventory: [.oracle],
        .extractableTotalKernel: [.oracle],
        .directInstantiation: [.cleanInstanceMethods],
        .concreteTypeUsage: [.cleanInstanceMethods],
        .couldBePrivate: [.oracle],
        .couldBePrivateMember: [.oracle],
        .unreachableEffectClosure: [.oracle]
    ]

    static func declared(_ rule: RuleIdentifier) -> PackagePurityInputs {
        registered.filter { $0.name == rule }.reduce(into: []) { $0.formUnion($1.packagePurityInputs) }
    }

    @Test("the declarations are the reviewed nine")
    func declarationInventory() {
        var declared: [RuleIdentifier: PackagePurityInputs] = [:]
        for rule in Self.ruleNames where !Self.declared(rule).isEmpty {
            declared[rule] = Self.declared(rule)
        }
        #expect(declared == Self.expectedDeclarations)
    }
}
