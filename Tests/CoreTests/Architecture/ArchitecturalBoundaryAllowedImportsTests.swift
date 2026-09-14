@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// `allowed_imports`: a layer that names the only frameworks it may import.
@Suite
struct ArchitecturalBoundaryAllowedImportsTests {

    private func issues(_ source: String, policy: LayerPolicy, filePath: String = "Domain/Order.swift") -> [LintIssue] {
        let visitor = ArchitecturalBoundaryVisitor(patternCategory: .architecture)
        visitor.layerPolicies = [policy]
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: filePath, tree: syntax))
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .architecturalBoundary }
    }

    private let domain = LayerPolicy(name: "domain", paths: ["Domain/"], allowedImports: ["Foundation"])

    // MARK: - Visitor

    @Test func flagsAnImportTheLayerDidNotAllow() throws {
        let found = issues("import Foundation\nimport Alamofire", policy: domain)

        let issue = try #require(found.first)
        #expect(found.count == 1)
        #expect(issue.lineNumber == 2)
        #expect(issue.message == "'Alamofire' is not an allowed import in the 'domain' layer")
    }

    @Test func admitsASubmoduleOfAnAllowedModule() {
        let policy = LayerPolicy(name: "ui", paths: ["Domain/"], allowedImports: ["UIKit"])
        #expect(issues("import UIKit.UIGestureRecognizerSubclass", policy: policy).isEmpty)
    }

    @Test func alwaysAdmitsTheStandardLibrary() {
        let nothingAllowed = LayerPolicy(name: "domain", paths: ["Domain/"], allowedImports: [])
        #expect(issues("import Swift", policy: nothingAllowed).isEmpty)
        #expect(issues("import Foundation", policy: nothingAllowed).count == 1)
    }

    @Test func reportsAModuleThatIsBothForbiddenAndUnlistedOnce() throws {
        let policy = LayerPolicy(
            name: "domain", paths: ["Domain/"], forbiddenImports: ["CoreData"], allowedImports: ["Foundation"]
        )
        let found = issues("import CoreData", policy: policy)

        #expect(found.count == 1)
        #expect(try #require(found.first).message.contains("must not be imported"))
    }

    @Test func aLayerWithoutAnAllowlistAdmitsEverythingNotForbidden() {
        let denyOnly = LayerPolicy(name: "domain", paths: ["Domain/"], forbiddenImports: ["CoreData"])
        #expect(issues("import Alamofire\nimport SwiftUI", policy: denyOnly).isEmpty)
    }

    @Test func filesOutsideTheLayerAreNotJudged() {
        #expect(issues("import Alamofire", policy: domain, filePath: "Networking/Client.swift").isEmpty)
    }

    // MARK: - Loader

    private func layers(_ yaml: String) -> [LayerPolicy] {
        let path = NSTemporaryDirectory() + "allowed-imports-\(UUID().uuidString).yml"
        try? yaml.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        return LintConfigurationLoader.load(from: path).architecturalLayers
    }

    @Test func parsesAllowedImports() throws {
        let layer = try #require(layers("""
        architectural_layers:
          domain:
            paths: ["Domain/"]
            allowed_imports: ["Foundation", "OSLog"]
        """).first)

        #expect(layer.allowedImports == ["Foundation", "OSLog"])
    }

    @Test func anEmptyListIsAnAllowlistButAnAbsentOrNullKeyIsNot() throws {
        let empty = try #require(layers("""
        architectural_layers:
          domain:
            paths: ["Domain/"]
            allowed_imports: []
        """).first)
        let absent = try #require(layers("""
        architectural_layers:
          domain:
            paths: ["Domain/"]
        """).first)
        let null = try #require(layers("""
        architectural_layers:
          domain:
            paths: ["Domain/"]
            allowed_imports:
        """).first)

        #expect(empty.allowedImports?.isEmpty == true)
        #expect(absent.allowedImports == nil)
        #expect(null.allowedImports == nil)
    }
}
