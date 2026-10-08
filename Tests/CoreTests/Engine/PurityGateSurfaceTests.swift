import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// The three package-purity surfaces a run can withhold — the oracle's table (`PackagePurity`), the
/// clean-method catalog and the join's settled names — each keep their storage in a `Withholdable`,
/// whose one read point trips the run's `PurityTripwire` when the value was withheld.
///
/// These pin the surfaces on their own, with no run: what counts as a read, that each read trips
/// once and names what it asked, and that the values a unit test gets (`.unconfigured`, `.empty`)
/// never trip. `PurityGateDeclarationTests` pins what a run does with the trips.
@Suite("A withheld package-purity surface trips on every read")
struct PurityGateSurfaceTests {

    @Test("creating an oracle under a withheld table trips once, naming where; every table accessor trips")
    func withheldTableTripsAtOracleCreation() throws {
        let function = try Self.first(FunctionDeclSyntax.self, in: "func f(_ n: Int) -> Int { n }")
        let tripwire = PurityTripwire()
        let withheld = PackagePurity.withheld(by: tripwire)
        let oracle = PackagePurity.$current.withValue(withheld) { PurityInferrer() }
        #expect(tripwire.recorded.map(\.input) == [.oracle])
        #expect(tripwire.recorded.first?.query.contains("PurityGateSurfaceTests.swift") == true,
                "the trip names the call site: \(tripwire.recorded)")
        // The table was taken at creation; asking the oracle reads nothing more.
        _ = oracle.isPure(function)
        #expect(tripwire.recorded.count == 1)

        _ = PurityInferrer(context: withheld)
        _ = withheld.universe
        _ = withheld.isEmpty
        _ = withheld.refutedTypes
        #expect(tripwire.recorded.count == 5)
        #expect(withheld.isWithheld && tripwire.recorded.count == 5, "asking isWithheld is not a read")

        // Outside a run nothing is withheld: the unconfigured table never trips.
        _ = PackagePurity.unconfigured.universe
        _ = PurityInferrer()
        #expect(tripwire.recorded.count == 5)
    }

    @Test("withheld catalogs trip on every read; the empty ones a unit test gets never do")
    func withheldCatalogsTrip() {
        let tripwire = PurityTripwire()
        let catalog = CleanInstanceMethodCatalog.withheld(by: tripwire)
        let join = ImpurePackageFunctions.withheld(by: tripwire)
        // Handing them on — the detector copying them into each visitor — is not a read.
        let copies = (catalog, join)
        #expect(tripwire.recorded.isEmpty)

        _ = copies.0.isPureKernel("T")
        _ = copies.0.cleanMethods(on: "T")
        _ = copies.0.isEmpty
        _ = copies.0 == .empty
        _ = copies.1.settledNames
        _ = copies.1 == .empty
        #expect(Set(tripwire.recorded.map(\.input.rawValue)) == [
            PackagePurityInputs.cleanInstanceMethods.rawValue, PackagePurityInputs.impurePackageFunctions.rawValue
        ])
        // `==` reads both sides, and the withheld side trips.
        #expect(tripwire.recorded.count == 6)

        // Unit tests drive visitors with these: no run, nothing withheld, nothing to trip.
        _ = CleanInstanceMethodCatalog.empty.isPureKernel("T")
        _ = ImpurePackageFunctions.empty.settledNames
        #expect(tripwire.recorded.count == 6)
    }

    static func first<Node: SyntaxProtocol>(_: Node.Type, in source: String) throws -> Node {
        let tree = Parser.parse(source: source)
        return try #require(tree.tokens(viewMode: .sourceAccurate).lazy.compactMap { token in
            sequence(first: Syntax(token)) { $0.parent }.lazy.compactMap { $0.as(Node.self) }.first
        }.first)
    }
}
