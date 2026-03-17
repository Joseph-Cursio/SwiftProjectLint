import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite
struct ArchAccessingImplDetailsTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = AccessingImplementationDetailsVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    // MARK: - Underscore-prefix heuristic

    @Test func testDetectsUnderscoreMemberOnOtherObject() throws {
        let source = """
        class Cache { var _data: [String] = [] }
        class Manager {
            let cache = Cache()
            func clear() { _ = cache._data }
        }
        """
        let issues = analyzeSource(source)
        let violations = issues.filter { $0.ruleName == .accessingImplementationDetails }
        #expect(violations.count == 1)
        #expect(violations[0].message.contains("_data"))
        #expect(violations[0].message.contains("cache"))
    }

    @Test func testDetectsDoubleUnderscoreMember() throws {
        let source = """
        class Backing { var __storage: Int = 0 }
        class Accessor {
            let obj = Backing()
            func read() -> Int { return obj.__storage }
        }
        """
        let issues = analyzeSource(source)
        let violations = issues.filter { $0.ruleName == .accessingImplementationDetails }
        #expect(violations.count == 1)
        #expect(violations[0].message.contains("__storage"))
    }

    @Test func testNoIssueForSelfUnderscoreAccess() throws {
        let source = """
        class MyClass {
            var _prop: Int = 0
            func read() -> Int { return self._prop }
        }
        """
        let issues = analyzeSource(source)
        let violations = issues.filter { $0.ruleName == .accessingImplementationDetails }
        #expect(violations.isEmpty)
    }

    @Test func testNoIssueForSuperUnderscoreAccess() throws {
        let source = """
        class Base { func _setup() {} }
        class Child: Base {
            override func _setup() { super._setup() }
        }
        """
        let issues = analyzeSource(source)
        let violations = issues.filter { $0.ruleName == .accessingImplementationDetails }
        #expect(violations.isEmpty)
    }

    @Test func testNoIssueForPublicMember() throws {
        let source = """
        class CacheManager { var data: [String] = [] }
        class Owner {
            let manager = CacheManager()
            func get() -> [String] { return manager.data }
        }
        """
        let issues = analyzeSource(source)
        let violations = issues.filter { $0.ruleName == .accessingImplementationDetails }
        #expect(violations.isEmpty)
    }

    @Test func testNoIssueForImplicitMember() throws {
        // Implicit `.someCase` has a nil base — should not trigger
        let source = """
        enum Color { case red, blue }
        func paint() -> Color { return .red }
        """
        let issues = analyzeSource(source)
        let violations = issues.filter { $0.ruleName == .accessingImplementationDetails }
        #expect(violations.isEmpty)
    }

    // MARK: - Force-cast bypass heuristic

    @Test func testDetectsForceCastToServiceType() throws {
        let source = """
        protocol Networking {}
        class NetworkService: Networking { var connectionPool: Int = 0 }
        func hack(n: Networking) {
            _ = (n as! NetworkService).connectionPool
        }
        """
        let issues = analyzeSource(source)
        let violations = issues.filter { $0.ruleName == .accessingImplementationDetails }
        #expect(violations.count == 1)
        #expect(violations.first?.message.contains("NetworkService") == true)
        #expect(violations.first?.message.contains("connectionPool") == true)
    }

    @Test func testNoIssueForForceCastToNonServiceType() throws {
        // UIButton does not end with a service-like suffix
        let source = """
        import UIKit
        func toggle(view: UIView) {
            _ = (view as! UIButton).isEnabled
        }
        """
        let issues = analyzeSource(source)
        let violations = issues.filter { $0.ruleName == .accessingImplementationDetails }
        #expect(violations.isEmpty)
    }

    @Test func testNoIssueForOptionalCast() throws {
        // `as?` should not trigger — only `as!`
        let source = """
        protocol Networking {}
        class NetworkService: Networking { var pool: Int = 0 }
        func safe(n: Networking) {
            _ = (n as? NetworkService)?.pool
        }
        """
        let issues = analyzeSource(source)
        let violations = issues.filter { $0.ruleName == .accessingImplementationDetails }
        #expect(violations.isEmpty)
    }

    // MARK: - Combined

    @Test func testDetectsMultipleViolations() throws {
        let source = """
        class DataStore { var _cache: [String] = [] }
        protocol Fetching {}
        class DataService: Fetching { var internalQueue: Int = 0 }
        class Consumer {
            let store = DataStore()
            func run(f: Fetching) {
                _ = store._cache
                _ = (f as! DataService).internalQueue
            }
        }
        """
        let issues = analyzeSource(source)
        let violations = issues.filter { $0.ruleName == .accessingImplementationDetails }
        #expect(violations.count == 2)
    }
}
