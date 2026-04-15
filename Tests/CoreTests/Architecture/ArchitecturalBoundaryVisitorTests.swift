import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct ArchitecturalBoundaryVisitorTests {

    // MARK: - Helper

    private func issues(
        _ source: String,
        filePath: String,
        policies: [LayerPolicy]
    ) -> [LintIssue] {
        let visitor = ArchitecturalBoundaryVisitor(patternCategory: .architecture)
        visitor.layerPolicies = policies
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .architecturalBoundary }
    }

    private let domainPolicy = LayerPolicy(
        name: "domain",
        paths: ["Domain/"],
        forbiddenImports: ["CoreData", "SwiftData", "UIKit", "SwiftUI"],
        forbiddenTypes: ["URLSession", "UserDefaults", "NSManagedObject"]
    )

    // MARK: - Import-based violations

    @Test func testForbiddenImportInLayer() throws {
        let source = """
        import Foundation
        import CoreData

        protocol UserRepository {}
        """
        let found = issues(source, filePath: "Domain/UserRepository.swift", policies: [domainPolicy])
        let issue = try #require(found.first)
        #expect(found.count == 1)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("CoreData"))
        #expect(issue.message.contains("domain"))
    }

    @Test func testMultipleForbiddenImports() {
        let source = """
        import CoreData
        import UIKit
        """
        let found = issues(source, filePath: "Domain/Foo.swift", policies: [domainPolicy])
        #expect(found.count == 2)
    }

    @Test func testAllowedImportInLayer() {
        let source = """
        import Foundation
        import Combine

        protocol OrderService {}
        """
        let found = issues(source, filePath: "Domain/OrderService.swift", policies: [domainPolicy])
        #expect(found.isEmpty)
    }

    // MARK: - Type-based violations

    @Test func testForbiddenTypeReferenceInLayer() throws {
        let source = """
        import Foundation

        class OrderService {
            func placeOrder() {
                let session = URLSession.shared
                _ = session
            }
        }
        """
        let found = issues(source, filePath: "Domain/OrderService.swift", policies: [domainPolicy])
        let issue = try #require(found.first)
        #expect(issue.message.contains("URLSession"))
        #expect(issue.message.contains("domain"))
    }

    @Test func testForbiddenTypeAnnotationInLayer() throws {
        let source = """
        import Foundation

        class SettingsService {
            var store: UserDefaults = .standard
        }
        """
        let found = issues(source, filePath: "Domain/SettingsService.swift", policies: [domainPolicy])
        #expect(found.isEmpty == false)
        #expect(found.first?.message.contains("UserDefaults") == true)
    }

    // MARK: - No-op when file is outside all layers

    @Test func testNoIssueForFileOutsideAllLayers() {
        let source = """
        import CoreData

        class PersistenceController {}
        """
        // Infrastructure/ is not in domain paths
        let found = issues(source, filePath: "Infrastructure/PersistenceController.swift", policies: [domainPolicy])
        #expect(found.isEmpty)
    }

    // MARK: - No-op when no policies configured

    @Test func testNoIssueWhenNoPoliciesConfigured() {
        let source = """
        import CoreData
        import UIKit

        class Anything {}
        """
        let found = issues(source, filePath: "Domain/Anything.swift", policies: [])
        #expect(found.isEmpty)
    }

    // MARK: - Multiple layers

    @Test func testPresentationLayerPolicy() throws {
        let presentationPolicy = LayerPolicy(
            name: "presentation",
            paths: ["ViewModels/"],
            forbiddenImports: ["CoreData"],
            forbiddenTypes: ["NSManagedObject"]
        )
        let source = """
        import CoreData
        """
        let found = issues(
            source, filePath: "ViewModels/OrderViewModel.swift",
            policies: [domainPolicy, presentationPolicy]
        )
        let issue = try #require(found.first)
        #expect(issue.message.contains("presentation"))
    }

    @Test func testEachLayerOnlyMatchesItsOwnPaths() {
        let presentationPolicy = LayerPolicy(
            name: "presentation",
            paths: ["ViewModels/"],
            forbiddenImports: ["CoreData"],
            forbiddenTypes: []
        )
        let source = """
        import CoreData
        """
        // This file is in Domain/, not ViewModels/ — should use domainPolicy
        let found = issues(source, filePath: "Domain/Foo.swift", policies: [domainPolicy, presentationPolicy])
        #expect(found.count == 1)
        #expect(found.first?.message.contains("domain") == true)
    }
}
