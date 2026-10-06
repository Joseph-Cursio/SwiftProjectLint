import SwiftEffectInference
@testable import SwiftProjectLintVisitors
import Testing

/// SEI `f2ea8d6` added `PurityRefutation.refutingConstruction`: constructing a type whose stored
/// default, initializer or superclass runs an effect. `Impurity` and `PackagePurityJoin` switch over
/// the refutation with no `default`, on purpose, so the new case had to be given a home by hand.
/// These pin the home it was given — the cause is the effect's, as for a default argument, and the
/// witness says where constructing the type reached it.
@Suite("Impurity — a construction is filed under the effect it reaches")
struct ImpurityConstructionTests {

    private let uuid = PurityRefutation.nondeterministicMarker("UUID")

    @Test("a stored default's construction is filed under its effect, naming the property")
    func storedProperty() throws {
        let impurity = try #require(Impurity(.refutingConstruction(
            type: "HealthRecommendation", via: .storedProperty("id"), cause: uuid
        )))
        #expect(impurity.cause == .nondeterminism)
        #expect(impurity.witness == "HealthRecommendation.id's default: UUID")
    }

    @Test("an initializer's and a superclass's construction name the step")
    func initializerAndSuperclass() throws {
        let viaInit = try #require(Impurity(.refutingConstruction(
            type: "Log", via: .initializer("init(path:)"), cause: .sideEffectMarker("FileManager")
        )))
        #expect(viaInit.cause == .sideEffect)
        #expect(viaInit.witness == "Log.init(path:): FileManager")

        let base = PurityRefutation.refutingConstruction(type: "Base", via: .storedProperty("id"), cause: uuid)
        let viaSuper = try #require(Impurity(.refutingConstruction(type: "Sub", via: .superclass("Base"), cause: base)))
        #expect(viaSuper.cause == .nondeterminism)
        #expect(viaSuper.witness == "Sub, a subclass of Base: Base.id's default: UUID")
    }

    @Test("a construction is evidence for the package join, not the oracle's blindness")
    func joinCountsItAsEvidence() {
        #expect(PackagePurityJoin.namesEvidence(.refutingConstruction(
            type: "T", via: .storedProperty("id"), cause: uuid
        )))
    }
}
