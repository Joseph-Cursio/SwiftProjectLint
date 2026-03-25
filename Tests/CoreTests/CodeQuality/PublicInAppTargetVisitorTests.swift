import Testing
import SwiftSyntax
import SwiftParser
@testable import Core

@Suite
struct PublicInAppTargetVisitorTests {

    private func analyze(_ source: String) -> [LintIssue] {
        let pattern = PublicInAppTarget().pattern
        let visitor = PublicInAppTargetVisitor(pattern: pattern)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: "Test.swift", tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath("Test.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .publicInAppTarget }
    }

    @Test func flagsPublicStruct() throws {
        let issues = analyze("public struct MyModel { let name: String }")
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("public struct MyModel"))
    }

    @Test func flagsPublicClass() {
        let issues = analyze("public class MyService { }")
        #expect(issues.count == 1)
    }

    @Test func flagsPublicEnum() {
        let issues = analyze("public enum Status { case active }")
        #expect(issues.count == 1)
    }

    @Test func flagsPublicFunc() {
        let issues = analyze("""
        struct Foo {
            public func doWork() { }
        }
        """)
        #expect(issues.count == 1)
    }

    @Test func flagsPublicVar() {
        let issues = analyze("""
        struct Foo {
            public var name: String = ""
        }
        """)
        #expect(issues.count == 1)
    }

    @Test func flagsOpenClass() throws {
        let issues = analyze("open class BaseController { }")
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("open class"))
    }

    @Test func flagsPublicInit() {
        let issues = analyze("""
        struct Foo {
            public init() { }
        }
        """)
        #expect(issues.count == 1)
    }

    @Test func flagsPublicProtocol() {
        let issues = analyze("public protocol Loadable { func load() }")
        #expect(issues.count == 1)
    }

    @Test func doesNotFlagInternalOrPrivate() {
        let issues = analyze("""
        struct InternalStruct { }
        internal class InternalClass { }
        private struct PrivateStruct { }
        fileprivate enum FileEnum { }
        """)
        #expect(issues.isEmpty)
    }

    @Test func flagsMultiplePublicDeclarations() {
        let issues = analyze("""
        public struct ModelA { }
        public struct ModelB { }
        struct InternalModel { }
        """)
        #expect(issues.count == 2)
    }
}
