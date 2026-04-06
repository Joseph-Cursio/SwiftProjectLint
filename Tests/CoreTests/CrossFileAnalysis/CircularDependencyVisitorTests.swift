import Testing
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct CircularDependencyVisitorTests {

    // MARK: - Helper

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = CircularDependency().pattern
        let visitor = CircularDependencyVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(
                SourceLocationConverter(fileName: name, tree: ast)
            )
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .circularDependency }
    }

    // MARK: - Positive: flags circular dependencies

    @Test func testFlagsSimpleCircularDependency() throws {
        let issues = analyze(files: [
            "UserManager.swift": """
            class UserManager {
                var sessionManager: SessionManager
            }
            """,
            "SessionManager.swift": """
            class SessionManager {
                var userManager: UserManager
            }
            """
        ])
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("UserManager"))
        #expect(issue.message.contains("SessionManager"))
    }

    @Test func testFlagsOptionalCircularDependency() throws {
        let issues = analyze(files: [
            "A.swift": """
            class TypeA {
                var ref: TypeB?
            }
            """,
            "B.swift": """
            class TypeB {
                var ref: TypeA?
            }
            """
        ])
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueForOneDirectionalRef() throws {
        let issues = analyze(files: [
            "A.swift": """
            class TypeA {
                var ref: TypeB
            }
            """,
            "B.swift": """
            class TypeB {
                var name: String
            }
            """
        ])
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesWeakReference() throws {
        let issues = analyze(files: [
            "Parent.swift": """
            class Parent {
                var child: Child
            }
            """,
            "Child.swift": """
            class Child {
                weak var parent: Parent?
            }
            """
        ])
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesProtocolReference() throws {
        let issues = analyze(files: [
            "UserManager.swift": """
            class UserManager {
                var sessionProvider: SessionProviding
            }
            """,
            "Protocol.swift": """
            protocol SessionProviding { }
            """,
            "SessionManager.swift": """
            class SessionManager: SessionProviding {
                var userManager: UserManager
            }
            """
        ])
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForSelfReference() throws {
        let issues = analyze(files: [
            "Node.swift": """
            class Node {
                var next: Node?
            }
            """
        ])
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForUnrelatedTypes() throws {
        let issues = analyze(files: [
            "A.swift": """
            class TypeA {
                var name: String
            }
            """,
            "B.swift": """
            class TypeB {
                var count: Int
            }
            """
        ])
        #expect(issues.isEmpty)
    }
}
