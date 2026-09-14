@testable import CLI
import Foundation
import SwiftProjectLintConfig
import SwiftProjectLintModels
import Testing

/// The CLI half of the layer-configuration diagnostic: the walk supplies root-relative paths, which
/// are what layer paths match. An absolute path would match no layer, and every configured path
/// would be reported as empty.
@Suite
struct LayerConfigurationAuditWalkTests {

    @Test func matchesLayerPathsAgainstRootRelativeFiles() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spl-layer-audit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Domain/Order.swift")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "struct Order {}".write(to: file, atomically: true, encoding: .utf8)

        let configuration = LintConfiguration(architecturalLayers: [
            LayerPolicy(name: "domain", paths: ["Domain/"]),
            LayerPolicy(name: "presentation", paths: ["Presentation/"])
        ])
        let problems = SwiftProjectLintCLI.layerConfigurationProblems(
            projectRoot: root.path, configuration: configuration
        )

        #expect(problems == [.pathMatchesNoFile(layer: "presentation", path: "Presentation/")])
    }

    @Test func skipsTheWalkWhenNoLayersAreConfigured() {
        #expect(SwiftProjectLintCLI.layerConfigurationProblems(
            projectRoot: "/nonexistent", configuration: LintConfiguration()
        ).isEmpty)
    }
}
