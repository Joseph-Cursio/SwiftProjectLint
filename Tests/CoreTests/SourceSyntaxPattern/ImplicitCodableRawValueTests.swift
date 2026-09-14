@testable import Core
import Foundation
import Testing

@Suite("Implicit Codable Raw Value")
@MainActor
struct ImplicitCodableRawValueTests {

    private func issues(_ source: String, filePath: String = "Sources/App/Models.swift") -> [LintIssue] {
        TestRegistryManager.getSharedDetector().detectPatterns(
            in: source,
            filePath: filePath,
            ruleIdentifiers: [.implicitCodableRawValue]
        )
    }

    // MARK: - Positive

    @Test func flagsAStringCodableEnumWithImplicitValues() throws {
        let found = issues("""
        import Foundation

        enum Status: String, Codable {
            case active
            case inactive = "inactive"
            case archived, pending
        }
        """)

        let issue = try #require(found.first)
        #expect(found.count == 1)
        #expect(issue.severity == .info)
        #expect(issue.lineNumber == 3)
        #expect(issue.message == "Codable enum 'Status' uses implicit raw values for 'active', 'archived', "
            + "'pending' — renaming a case changes its encoded value")
        #expect(issue.suggestion?.contains(#"case active = "active""#) == true)
    }

    @Test func eachCodableProtocolAndQualifiedSpellingCounts() {
        #expect(issues("enum A: String, Encodable { case one }").count == 1)
        #expect(issues("enum B: String, Decodable { case one }").count == 1)
        #expect(issues("enum C: Swift.String, Swift.Codable { case one }").count == 1)
        #expect(issues("enum D: String, CaseIterable, Sendable, Codable { case one }").count == 1)
    }

    @Test func countsAConformanceAddedByAnExtensionInTheSameFile() {
        let found = issues("""
        enum Status: String { case active }
        extension Status: Codable {}
        """)

        #expect(found.count == 1)
    }

    @Test func findsCasesInsideConditionalCompilation() {
        let found = issues("""
        enum Platform: String, Codable {
            case web = "web"
            #if os(iOS)
            case phone
            #endif
        }
        """)

        #expect(found.first?.message.contains("'phone'") == true)
    }

    @Test func summarisesALongListOfCases() {
        let found = issues("enum Letter: String, Codable { case a, b, c, d, e }")

        #expect(found.first?.message.contains("'a', 'b', 'c' and 2 more") == true)
    }

    @Test func stripsBackticksFromAnEscapedCaseName() throws {
        let found = issues("enum Mode: String, Codable { case `default` }")

        let issue = try #require(found.first)
        #expect(issue.message.contains("'default'"))
        #expect(issue.suggestion?.contains(#"case `default` = "default""#) == true)
    }

    @Test func checksNestedEnums() {
        let found = issues("""
        struct Order: Codable {
            enum State: String, Codable { case open }
            let state: State
        }
        """)

        #expect(found.count == 1)
    }

    // MARK: - Negative

    @Test func testAndFixtureFilesAreNotJudged() {
        let source = "enum Fixture: String, Codable { case one }"
        #expect(issues(source, filePath: "Tests/AppTests/RouterTests.swift").isEmpty)
        #expect(issues(source, filePath: "Sources/AppTests/Fixtures.swift").isEmpty)
        #expect(issues(source).count == 1)
    }

    @Test func explicitValuesOnEveryCaseAreFine() {
        #expect(issues("""
        enum Status: String, Codable {
            case active = "active"
            case inactive = "disabled"
        }
        """).isEmpty)
    }

    @Test func aStringEnumThatIsNotCodableIsNotJudged() {
        #expect(issues("enum Tab: String, CaseIterable { case home, settings }").isEmpty)
    }

    @Test func codingKeysAreNotJudged() {
        #expect(issues("""
        struct User: Codable {
            let name: String
            enum CodingKeys: String, CodingKey { case name }
        }
        """).isEmpty)
    }

    @Test func integerBackedEnumsAreNotJudged() {
        #expect(issues("enum Priority: Int, Codable { case low, high }").isEmpty)
    }

    @Test func aStringThatIsNotTheRawTypeDoesNotCount() {
        // Swift requires the raw type first, so `String` anywhere else is not a raw type — this does
        // not compile as a raw-value enum, and the rule must not read it as one.
        #expect(issues("enum Weird: Codable, String { case one }").isEmpty)
    }

    @Test func handWrittenCodingIsNotJudged() {
        #expect(issues("""
        enum Status: String, Codable {
            case active
            init(from decoder: Decoder) throws { self = .active }
        }
        """).isEmpty)
        #expect(issues("""
        enum Status: String, Codable {
            case active
        }
        extension Status {
            func encode(to encoder: Encoder) throws {}
        }
        """).isEmpty)
    }
}
