import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite
@MainActor
struct ArchitectureDirectInstantiationTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = DirectInstantiationVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    // MARK: - Stored property

    @Test func testDetectsDirectInstantiationInStoredProperty() throws {
        let source = """
        class MyView {
            private let svc = NetworkService()
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        #expect(directIssues.count == 1)
        #expect(directIssues[0].message.contains("NetworkService"))
    }

    // MARK: - Constructor default

    @Test func testDetectsDirectInstantiationInConstructorDefault() throws {
        let source = """
        class MyViewModel {
            init(svc: NetworkService = NetworkService()) { }
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        #expect(directIssues.count == 1)
        #expect(directIssues[0].message.contains("NetworkService"))
    }

    // MARK: - Function body

    @Test func testDetectsDirectInstantiationInFunctionBody() throws {
        let source = """
        class Setup {
            func setup() {
                let svc = NetworkService()
                _ = svc
            }
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        #expect(directIssues.count == 1)
        #expect(directIssues[0].message.contains("NetworkService"))
    }

    // MARK: - Closure

    @Test func testDetectsDirectInstantiationInClosure() throws {
        let source = """
        class Owner {
            var fn: () -> Void = {
                let repo = UserRepository()
                _ = repo
            }
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        #expect(directIssues.count == 1)
        #expect(directIssues[0].message.contains("UserRepository"))
    }

    // MARK: - No issue for injected dependency

    @Test func testNoIssueForInjectedDependency() throws {
        let source = """
        class MyViewModel {
            private let service: NetworkService
            init(service: NetworkService) {
                self.service = service
            }
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        #expect(directIssues.isEmpty)
    }

    // MARK: - No issue for property wrapper instantiation

    @Test func testNoIssueForPropertyWrapperInstantiation() throws {
        let source = """
        import SwiftUI
        struct MyView: View {
            @StateObject private var vm = MyViewModel()
            var body: some View { Text("") }
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        #expect(directIssues.isEmpty)
    }

    // MARK: - No issue for non-matching types

    @Test func testNoIssueForValueTypes() throws {
        let source = """
        class Owner {
            let counter = Counter()
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        #expect(directIssues.isEmpty)
    }

    // MARK: - Multiple instantiations

    @Test func testDetectsMultipleInstantiations() throws {
        let source = """
        class Owner {
            let apiClient = APIClient()
            let dataStore = UserDataStore()
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        #expect(directIssues.count == 2)
    }
}
