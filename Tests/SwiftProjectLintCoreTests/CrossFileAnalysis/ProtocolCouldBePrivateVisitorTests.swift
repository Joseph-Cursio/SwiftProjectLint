import Testing
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite
struct ProtocolCouldBePrivateVisitorTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = ProtocolCouldBePrivate().pattern
        let visitor = ProtocolCouldBePrivateVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .protocolCouldBePrivate }
    }

    @Test func flagsProtocolOnlyUsedInDeclaringFile() {
        let issues = analyze(files: [
            "Service.swift": """
            protocol Loadable {
                func load()
            }
            struct DataService: Loadable {
                func load() { }
            }
            """,
            "Other.swift": """
            struct Other { }
            """
        ])

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Loadable") == true)
    }

    @Test func doesNotFlagProtocolUsedAcrossFiles() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol Loadable {
                func load()
            }
            """,
            "Conformer.swift": """
            struct DataService: Loadable {
                func load() { }
            }
            """
        ])

        let flagged = issues.map { $0.message }
        #expect(!flagged.contains { $0.contains("Loadable") })
    }

    @Test func doesNotFlagProtocolUsedAsTypeAnnotation() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol Fetchable {
                func fetch()
            }
            """,
            "Consumer.swift": """
            struct Manager {
                let fetcher: Fetchable
            }
            """
        ])

        let flagged = issues.map { $0.message }
        #expect(!flagged.contains { $0.contains("Fetchable") })
    }

    @Test func skipsAlreadyPrivateProtocol() {
        let issues = analyze(files: [
            "File.swift": """
            private protocol InternalOnly {
                func work()
            }
            struct Worker: InternalOnly {
                func work() { }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    @Test func skipsPublicProtocol() {
        let issues = analyze(files: [
            "File.swift": """
            public protocol SharedAPI {
                func call()
            }
            struct Client: SharedAPI {
                func call() { }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    @Test func flagsMultipleFileLocalProtocols() {
        let issues = analyze(files: [
            "FileA.swift": """
            protocol AlphaProtocol { func alpha() }
            struct AlphaImpl: AlphaProtocol { func alpha() { } }
            """,
            "FileB.swift": """
            protocol BetaProtocol { func beta() }
            struct BetaImpl: BetaProtocol { func beta() { } }
            """
        ])

        #expect(issues.count == 2)
    }
}
