@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Which layer a file belongs to when more than one layer's paths contain it.
@Suite
struct LayerPolicyLookupTests {

    private let features = LayerPolicy(name: "features", paths: ["Features/"])
    private let payments = LayerPolicy(name: "payments", paths: ["Features/Payments/"])
    private let shared = LayerPolicy(name: "shared", paths: ["Shared/", "Features/Payments/"])

    @Test func theMostSpecificMatchingPathWins() {
        let file = "Features/Payments/Checkout.swift"
        #expect(LayerPolicy.layer(for: file, in: [features, payments])?.name == "payments")
        #expect(LayerPolicy.layer(for: "Features/Orders/List.swift", in: [features, payments])?.name == "features")
    }

    @Test func anExactTieFallsToTheLayerName() {
        #expect(LayerPolicy.layer(for: "Features/Payments/Card.swift", in: [shared, payments])?.name == "payments")
    }

    @Test func noLayerContainsAFileOutsideEveryPath() {
        #expect(LayerPolicy.layer(for: "App/Main.swift", in: [features, payments, shared]) == nil)
    }

    /// The layers come from a YAML map, whose order is a hash seed's. Every ordering must agree.
    @Test func theAnswerDoesNotDependOnTheOrderLayersArriveIn() {
        let policies = [features, payments, shared]
        let orderings = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        for path in ["Features/Payments/Card.swift", "Features/Orders/List.swift", "Shared/Log.swift"] {
            let answers = Set(orderings.map { order in
                LayerPolicy.layer(for: path, in: order.map { policies[$0] })?.name
            })
            #expect(answers.count == 1, "\(path) resolved to \(answers)")
        }
    }

    @Test func theBoundaryRuleAppliesTheMoreSpecificLayersPolicy() {
        let outer = LayerPolicy(name: "features", paths: ["Features/"])
        let inner = LayerPolicy(name: "payments", paths: ["Features/Payments/"], forbiddenImports: ["UIKit"])

        let visitor = ArchitecturalBoundaryVisitor(patternCategory: .architecture)
        visitor.layerPolicies = [outer, inner]
        let path = "Features/Payments/CardView.swift"
        let syntax = Parser.parse(source: "import UIKit")
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: path, tree: syntax))
        visitor.setFilePath(path)
        visitor.walk(syntax)

        let issues = visitor.detectedIssues.filter { $0.ruleName == .architecturalBoundary }
        #expect(issues.map(\.message) == ["'UIKit' must not be imported in the 'payments' layer"])
    }
}
