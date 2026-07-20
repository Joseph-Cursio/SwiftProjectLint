@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct PrimitiveBypassingDomainTypeVisitorTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = PrimitiveBypassingDomainType().pattern
        let visitor = PrimitiveBypassingDomainTypeVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .primitiveBypassingDomainType }
    }

    /// The canonical case: a `String` newtype keys one map; a same-value-type sibling is still
    /// keyed by the raw `String`. One issue on the raw-keyed map only.
    @Test
    func rawStringKeyBesideWrapperKeyFlags() throws {
        let issues = analyze(files: [
            "Key.swift": "struct IdempotencyKey { let value: String }",
            "Store.swift": """
            struct Store {
                var seen: [IdempotencyKey: Response] = [:]
                var replayCache: [String: Response] = [:]
            }
            """
        ])

        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("IdempotencyKey"))
        #expect(issue.message.contains("String"))
        #expect(issue.lineNumber == 3) // the [String: Response] line
    }

    /// The false-positive guard: a raw `[String: X]` with no wrapper keyed to that value type is
    /// left alone — `String` keys unrelated maps everywhere.
    @Test
    func rawStringKeyWithoutMatchingWrapperValueClean() {
        let issues = analyze(files: [
            "Key.swift": "struct IdempotencyKey { let value: String }",
            "Store.swift": """
            struct Store {
                var seen: [IdempotencyKey: Response] = [:]
                var flags: [String: Bool] = [:]
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// No wrapper is ever used as a key — the undecidable "should this String be a type?"
    /// half the rule deliberately does not attempt.
    @Test
    func wrapperExistsButNeverKeyedClean() {
        let issues = analyze(files: [
            "Key.swift": "struct IdempotencyKey { let value: String }",
            "Store.swift": "struct Store { var responses: [String: Response] = [:] }"
        ])

        #expect(issues.isEmpty)
    }

    /// Both maps key by the domain type — consistent, nothing to report.
    @Test
    func bothMapsKeyedByWrapperClean() {
        let issues = analyze(files: [
            "Key.swift": "struct IdempotencyKey { let value: String }",
            "Store.swift": """
            struct Store {
                var seen: [IdempotencyKey: Response] = [:]
                var pending: [IdempotencyKey: Response] = [:]
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// A struct with two stored properties is not a newtype wrapper, so a raw key is not a bypass.
    @Test
    func multiFieldStructIsNotAWrapperClean() {
        let issues = analyze(files: [
            "Key.swift": "struct Pair { let value: String; let label: String }",
            "Store.swift": """
            struct Store {
                var byPair: [Pair: Response] = [:]
                var byString: [String: Response] = [:]
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// The long `Dictionary<Key, Value>` form is recognized the same as `[Key: Value]` sugar.
    @Test
    func longDictionaryFormFlags() {
        let issues = analyze(files: [
            "Key.swift": "struct UserID { let raw: UUID }",
            "Store.swift": """
            struct Store {
                var byID: Dictionary<UserID, Profile> = [:]
                var byRaw: Dictionary<UUID, Profile> = [:]
            }
            """
        ])

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("UserID") == true)
        #expect(issues.first?.message.contains("UUID") == true)
    }

    /// Cross-file: the wrapper, the wrapper-keyed map, and the raw-keyed map can each live in a
    /// different file — a single-file linter never sees the inconsistency.
    @Test
    func crossFileInconsistencyFlags() {
        let issues = analyze(files: [
            "Key.swift": "struct IdempotencyKey { let value: String }",
            "Good.swift": "struct A { var seen: [IdempotencyKey: Response] = [:] }",
            "Bad.swift": "struct B { var cache: [String: Response] = [:] }"
        ])

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("IdempotencyKey") == true)
    }
}
