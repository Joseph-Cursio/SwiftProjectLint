@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct LayerDependencyVisitorTests {

    // MARK: - Helpers

    private func analyze(_ files: [String: String], policies: [LayerPolicy]) -> [LintIssue] {
        let cache = files.mapValues { Parser.parse(source: $0) }
        let visitor = LayerDependencyVisitor(fileCache: cache)
        visitor.setPattern(LayerDependency().pattern)
        visitor.layerPolicies = policies
        for (name, ast) in cache.sorted(by: { $0.key < $1.key }) {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .layerDependency }
    }

    /// Presentation may use Domain; Persistence implements Domain's protocols.
    private let layers = [
        LayerPolicy(name: "domain", paths: ["Domain/"], mayDependOn: []),
        LayerPolicy(name: "persistence", paths: ["Persistence/"], mayDependOn: ["domain"]),
        LayerPolicy(name: "presentation", paths: ["Presentation/"], mayDependOn: ["domain"])
    ]

    private let declarations = [
        "Domain/Order.swift": "struct Order {}\nprotocol OrderStore {}",
        "Persistence/CoreDataOrderStore.swift": "final class CoreDataOrderStore: OrderStore {}"
    ]

    private func files(adding extra: [String: String]) -> [String: String] {
        declarations.merging(extra) { _, new in new }
    }

    // MARK: - Positive

    @Test func flagsATypeAnnotationNamingAForbiddenLayersType() throws {
        let issues = analyze(files(adding: [
            "Presentation/CheckoutViewModel.swift": """
            final class CheckoutViewModel {
                let order: Order
                let store: CoreDataOrderStore
            }
            """
        ]), policies: layers)

        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .warning)
        #expect(issue.filePath == "Presentation/CheckoutViewModel.swift")
        #expect(issue.lineNumber == 3)
        #expect(issue.message == "The 'presentation' layer references 'CoreDataOrderStore' from the "
            + "'persistence' layer, which it may not depend on")
    }

    @Test func flagsAConstructionOrStaticAccessInAnExpression() {
        let issues = analyze(files(adding: [
            "Presentation/Factory.swift": "func makeStore() -> Any { CoreDataOrderStore() }"
        ]), policies: layers)

        #expect(issues.count == 1)
    }

    @Test func flagsExtendingAnotherLayersType() {
        let issues = analyze(files(adding: [
            "Presentation/Store+Display.swift": "extension CoreDataOrderStore {}"
        ]), policies: layers)

        #expect(issues.count == 1)
    }

    @Test func reportsEachTypeOncePerFileAtItsFirstReference() throws {
        let issues = analyze(files(adding: [
            "Presentation/Many.swift": """
            let first = CoreDataOrderStore()
            let second: CoreDataOrderStore = CoreDataOrderStore()
            """
        ]), policies: layers)

        #expect(issues.count == 1)
        #expect(try #require(issues.first).lineNumber == 1)
    }

    // MARK: - Negative

    @Test func permitsItsOwnAndItsPermittedLayersTypes() {
        let issues = analyze(files(adding: [
            "Presentation/OrderRow.swift": "struct OrderRow { let order: Order }",
            "Presentation/OrderList.swift": "struct OrderList { let rows: [OrderRow] }"
        ]), policies: layers)

        #expect(issues.isEmpty)
    }

    @Test func aMemberNameAfterADotIsNotATypeReference() {
        let issues = analyze(files(adding: [
            "Presentation/Routes.swift": "enum Route { case CoreDataOrderStore }\nlet route = Route.CoreDataOrderStore"
        ]), policies: layers)

        #expect(issues.isEmpty)
    }

    @Test func aNameDeclaredInTwoPlacesIsNotAttributed() {
        let ambiguousInLayers = analyze(files(adding: [
            "Presentation/Uses.swift": "let value: CoreDataOrderStore? = nil",
            "Domain/Duplicate.swift": "struct CoreDataOrderStore {}"
        ]), policies: layers)
        let ambiguousWithUnlayered = analyze(files(adding: [
            "Presentation/Uses.swift": "let value: CoreDataOrderStore? = nil",
            "Support/Duplicate.swift": "struct CoreDataOrderStore {}"
        ]), policies: layers)

        #expect(ambiguousInLayers.isEmpty)
        #expect(ambiguousWithUnlayered.isEmpty)
    }

    @Test func aNameTheFileDeclaresItselfMeansItsOwnType() {
        let issues = analyze(files(adding: [
            "Presentation/Local.swift": """
            struct Screen {
                struct CoreDataOrderStore {}
                let store = CoreDataOrderStore()
            }
            func wrap<CoreDataOrderStore>(_ value: CoreDataOrderStore) {}
            """
        ]), policies: layers)

        #expect(issues.isEmpty)
    }

    @Test func aNestedTypeIsAttributedThroughItsOuterType() throws {
        var extra = files(adding: [
            "Presentation/Nested.swift": "let request: CoreDataOrderStore.Request? = nil"
        ])
        extra["Persistence/CoreDataOrderStore.swift"] = "final class CoreDataOrderStore { struct Request {} }"
        let issues = analyze(extra, policies: layers)

        #expect(issues.count == 1)
        #expect(try #require(issues.first).message.contains("'CoreDataOrderStore'"))
    }

    @Test func aLayerWithoutMayDependOnIsNotChecked() {
        let unconstrained = [
            LayerPolicy(name: "persistence", paths: ["Persistence/"]),
            LayerPolicy(name: "presentation", paths: ["Presentation/"], forbiddenImports: ["CoreData"]),
            LayerPolicy(name: "domain", paths: ["Domain/"], mayDependOn: [])
        ]
        let issues = analyze(files(adding: [
            "Presentation/Uses.swift": "let store = CoreDataOrderStore()"
        ]), policies: unconstrained)

        #expect(issues.isEmpty)
    }

    @Test func filesOutsideEveryLayerAreNotJudged() {
        let issues = analyze(files(adding: [
            "App/Composition.swift": "let store = CoreDataOrderStore()"
        ]), policies: layers)

        #expect(issues.isEmpty)
    }

    // MARK: - Configuration

    @Test func parsesMayDependOn() throws {
        let path = NSTemporaryDirectory() + "may-depend-on-\(UUID().uuidString).yml"
        try """
        architectural_layers:
          presentation:
            paths: ["Presentation/"]
            may_depend_on: ["domain"]
          domain:
            paths: ["Domain/"]
        """.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let loaded = LintConfigurationLoader.load(from: path).architecturalLayers

        #expect(loaded.first { $0.name == "presentation" }?.mayDependOn == ["domain"])
        #expect(loaded.first { $0.name == "domain" }?.mayDependOn == nil)
    }

    /// The layers reach this rule through the cross-file engine, which never had to carry them
    /// before. A real run from a config file is the only way to see that they arrive.
    @Test func aConfiguredProjectRunReportsTheDependency() async throws {
        let root = (FileManager.default.temporaryDirectory.path as NSString)
            .appendingPathComponent("LayerDependencyE2E-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(atPath: root) }
        let project: [String: String] = files(adding: [
            "Presentation/CheckoutViewModel.swift": "final class CheckoutViewModel { let store: CoreDataOrderStore }",
            ".swiftprojectlint.yml": """
            enabled_only:
              - "Layer Dependency"
            architectural_layers:
              domain:
                paths: ["Domain/"]
              persistence:
                paths: ["Persistence/"]
              presentation:
                paths: ["Presentation/"]
                may_depend_on: ["domain"]
            """
        ])
        for (relative, content) in project {
            let path = (root as NSString).appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true
            )
            try content.write(toFile: path, atomically: true, encoding: .utf8)
        }

        let system = PatternRegistryFactory.createConfiguredSystem()
        let issues = await ProjectLinter().analyzeProject(
            at: root, detector: system.detector, configuration: LintConfigurationLoader.load(projectRoot: root)
        )

        #expect(issues.filter { $0.ruleName == .layerDependency }.count == 1)
    }
}
