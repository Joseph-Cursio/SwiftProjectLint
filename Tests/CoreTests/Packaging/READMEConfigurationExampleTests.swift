@testable import Core
import Foundation
import Testing

/// The README's configuration example must configure what it claims to.
///
/// It wrote `architectural_layers` as a YAML list (`- name: domain`) while the loader reads a map
/// keyed by layer name. A list is not a map, so the loader returned no layers: a reader who copied
/// the example got a rule that reported nothing, with no error to say the block had been ignored.
/// The rule's own doc used the map form all along, so the two disagreed and only one worked.
///
/// Parsing the README's own text keeps the example honest in the way `READMERuleCountTests` keeps
/// its counts honest: the next change to either the prose or the loader has to agree with the other.
@Suite("Packaging — the README's configuration example loads")
struct READMEConfigurationExampleTests {

    private static var readme: String {
        get throws {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // Packaging
                .deletingLastPathComponent()   // CoreTests
                .deletingLastPathComponent()   // Tests
                .deletingLastPathComponent()   // repository root
                .appendingPathComponent("README.md")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    /// The fenced YAML block that configures `architectural_layers`.
    private static func configurationExample() throws -> String {
        let blocks = try readme.components(separatedBy: "```yaml").dropFirst()
            .compactMap { $0.components(separatedBy: "```").first }
        return try #require(blocks.first { $0.contains("architectural_layers:") })
    }

    @Test func theArchitecturalLayersExampleConfiguresItsLayers() throws {
        let path = NSTemporaryDirectory() + "readme-config-\(UUID().uuidString).yml"
        try Self.configurationExample().write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let layers = LintConfigurationLoader.load(from: path).architecturalLayers

        #expect(Set(layers.map(\.name)) == ["domain", "presentation"])
        #expect(layers.first { $0.name == "domain" }?.forbiddenImports.contains("CoreData") == true)
    }
}
