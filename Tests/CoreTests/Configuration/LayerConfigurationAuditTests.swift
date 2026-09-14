@testable import Core
import Testing

@Suite
struct LayerConfigurationAuditTests {

    private let files = [
        "Domain/Order.swift",
        "Persistence/Store.swift",
        "Presentation/CheckoutViewModel.swift"
    ]

    private func problems(_ layers: [LayerPolicy]) -> [LayerConfigurationAudit.Problem] {
        LayerConfigurationAudit.problems(in: layers, analysedFiles: files)
    }

    @Test func aSoundConfigurationHasNoProblems() {
        #expect(problems([
            LayerPolicy(name: "domain", paths: ["Domain/"], mayDependOn: []),
            LayerPolicy(name: "persistence", paths: ["Persistence/"], mayDependOn: ["domain"]),
            LayerPolicy(name: "presentation", paths: ["Presentation/"], mayDependOn: ["domain", "presentation"])
        ]).isEmpty)
    }

    @Test func reportsAPathUnderWhichNoFileLives() {
        #expect(problems([
            LayerPolicy(name: "domain", paths: ["Domian/", "Domain/"])
        ]) == [.pathMatchesNoFile(layer: "domain", path: "Domian/")])
    }

    @Test func reportsADependencyOnALayerThatDoesNotExist() {
        #expect(problems([
            LayerPolicy(name: "domain", paths: ["Domain/"]),
            LayerPolicy(name: "presentation", paths: ["Presentation/"], mayDependOn: ["domian"])
        ]) == [.unknownDependency(layer: "presentation", dependency: "domian")])
    }

    @Test func reportsLayersThatMayDependOnEachOtherOnce() {
        let found = problems([
            LayerPolicy(name: "domain", paths: ["Domain/"], mayDependOn: ["persistence"]),
            LayerPolicy(name: "persistence", paths: ["Persistence/"], mayDependOn: ["presentation"]),
            LayerPolicy(name: "presentation", paths: ["Presentation/"], mayDependOn: ["domain"])
        ])

        let expected = LayerConfigurationAudit.Problem.cycle(
            layers: ["domain", "persistence", "presentation"],
            path: ["domain", "persistence", "presentation", "domain"]
        )
        #expect(found == [expected])
    }

    @Test func aLayerListingItselfIsNotACycle() {
        #expect(problems([
            LayerPolicy(name: "domain", paths: ["Domain/"], mayDependOn: ["domain"])
        ]).isEmpty)
    }

    @Test func theNoticeNamesEveryProblem() {
        let notice = LayerConfigurationAudit.notice(for: [
            .pathMatchesNoFile(layer: "domain", path: "Domian/"),
            .cycle(layers: ["a", "b"], path: ["a", "b", "a"])
        ])

        #expect(notice.hasPrefix("Warning: architectural_layers has 2 problems"))
        #expect(notice.contains("layer 'domain': path 'Domian/' matches no analysed file"))
        #expect(notice.contains("layers 'a' → 'b' → 'a' may depend on each other"))
    }
}
