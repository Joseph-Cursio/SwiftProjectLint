@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct AccessingImplDetailsTests {

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

    /// As above, but with the project-wide prescan supplied.
    private func analyzeSource(
        _ source: String,
        declaredUnderscoredMembers: Set<String>,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = AccessingImplementationDetailsVisitor(patternCategory: .architecture)
        visitor.knownUnderscoredMembers = declaredUnderscoredMembers
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    // MARK: - Intra-module underscore access

    /// A member the project itself declares is the module's own convention, not a caller
    /// reaching past an interface — the same idea as the `@_spi` exemption, one scope wider
    /// than `enclosingTypeDeclares`, which only reaches the declaring type.
    ///
    /// Measured on 1.78M lines of Apple / swiftlang / Swift server WG code this rule reported
    /// 5,600 findings at 3.14 per 1,000 lines against 0.01 here. `swift-atomics` alone gave
    /// 927 — the highest density any repository has produced for any rule in this tool.
    @Test func aMemberTheProjectDeclaresIsNotAnImplementationDetail() {
        let source = """
        struct Slot { var _value: Int }
        struct Other {
            func read(_ slot: Slot) -> Int { slot._value }
        }
        """
        let issues = analyzeSource(source, declaredUnderscoredMembers: ["_value"])
        #expect(issues.filter { $0.ruleName == .accessingImplementationDetails }.isEmpty)
    }

    /// The case the rule exists for, and the one the exemption must not swallow: a name the
    /// project never declares is somebody else's internal.
    @Test func aMemberTheProjectDoesNotDeclareIsStillReported() throws {
        let source = """
        struct Other {
            func read(_ dep: SomeDependency) -> Int { dep._internalCounter }
        }
        """
        let issues = analyzeSource(source, declaredUnderscoredMembers: ["_value"])
        let violation = try #require(issues.first { $0.ruleName == .accessingImplementationDetails })
        #expect(violation.message.contains("_internalCounter"))
    }

    /// Without the prescan the rule behaves exactly as before — the exemption is additive, so
    /// an empty catalog cannot silence anything.
    @Test func anEmptyPrescanChangesNothing() throws {
        let source = """
        struct Slot { var _value: Int }
        struct Other {
            func read(_ slot: Slot) -> Int { slot._value }
        }
        """
        let issues = analyzeSource(source, declaredUnderscoredMembers: [])
        #expect(issues.contains { $0.ruleName == .accessingImplementationDetails })
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
        let violation = try #require(violations.first)
        #expect(violation.message.contains("_data"))
        #expect(violation.message.contains("cache"))
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
        let violation = try #require(violations.first)
        #expect(violation.message.contains("__storage"))
    }

    @Test func testNoIssueForSelfUnderscoreAccess() {
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

    @Test func testNoIssueForCapitalSelfUnderscoreAccess() {
        let source = """
        struct Config {
            static var _all: [Config] = []
            static func reset() { Self._all.removeAll() }
        }
        """
        let issues = analyzeSource(source)
        let violations = issues.filter { $0.ruleName == .accessingImplementationDetails }
        #expect(violations.isEmpty)
    }

    @Test func testNoIssueForSuperUnderscoreAccess() {
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

    @Test func testNoIssueForPublicMember() {
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

    @Test func testNoIssueForImplicitMember() {
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
        let violation = try #require(violations.first)
        #expect(violation.message.contains("NetworkService"))
        #expect(violation.message.contains("connectionPool"))
    }

    @Test func testNoIssueForForceCastToNonServiceType() {
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

    @Test func testNoIssueForOptionalCast() {
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

    @Test func testDetectsMultipleViolations() {
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
