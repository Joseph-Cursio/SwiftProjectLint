@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct PrimitiveNamedForDomainTypeVisitorTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = PrimitiveNamedForDomainType().pattern
        let visitor = PrimitiveNamedForDomainTypeVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .primitiveNamedForDomainType }
    }

    /// A parameter named for the wrapper but typed as the raw carrier.
    @Test
    func parameterNamedForWrapperFlags() throws {
        let issues = analyze(files: [
            "Key.swift": "struct IdempotencyKey { let value: String }",
            "Handler.swift": "func process(idempotencyKey: String) {}"
        ])

        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("IdempotencyKey"))
        #expect(issue.message.contains("idempotencyKey"))
    }

    /// A stored property named for the wrapper, cross-file, typed as the carrier.
    @Test
    func propertyNamedForWrapperFlags() {
        let issues = analyze(files: [
            "ID.swift": "struct UserID { let raw: UUID }",
            "Session.swift": "struct Session { let userID: UUID }"
        ])

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("UserID") == true)
    }

    /// Already typed as the domain newtype — nothing to enforce.
    @Test
    func alreadyTypedAsWrapperClean() {
        let issues = analyze(files: [
            "Key.swift": "struct IdempotencyKey { let value: String }",
            "Handler.swift": "func process(idempotencyKey: IdempotencyKey) {}"
        ])

        #expect(issues.isEmpty)
    }

    /// A name that doesn't match any wrapper is not the name-correspondence signal.
    @Test
    func unrelatedNameClean() {
        let issues = analyze(files: [
            "Key.swift": "struct IdempotencyKey { let value: String }",
            "Cache.swift": "func cache(key: String) {}"
        ])

        #expect(issues.isEmpty)
    }

    /// The carrier must match: a same-named position over a *different* primitive is ignored.
    @Test
    func nameMatchDifferentCarrierClean() {
        let issues = analyze(files: [
            "Key.swift": "struct IdempotencyKey { let value: String }",
            "Odd.swift": "func f(idempotencyKey: Int) {}"
        ])

        #expect(issues.isEmpty)
    }

    /// The wrapper's own backing field, when it happens to share the wrapper's name, is not
    /// flagged — the rule must never nag the very cure it enforces.
    @Test
    func wrapperOwnBackingFieldNotFlagged() {
        let issues = analyze(files: [
            "Percentage.swift": "struct Percentage { let percentage: Int }"
        ])

        #expect(issues.isEmpty)
    }

    /// A generic-word wrapper (`Name`, `Value`, `Text`) is too common to trust the name
    /// signal — `name: String` collides with it by coincidence, so it is not a trigger.
    /// (Measured as the dominant false-positive source across real projects.)
    @Test
    func genericWrapperNameSuppressed() {
        let issues = analyze(files: [
            "Name.swift": "struct Name { let value: String }",
            "User.swift": "func create(name: String) {}"
        ])

        #expect(issues.isEmpty)
    }

    /// A distinctive wrapper name still fires — the stop-list targets generic words only.
    @Test
    func distinctiveWrapperStillFires() {
        let issues = analyze(files: [
            "Key.swift": "struct SessionID { let value: String }",
            "Use.swift": "func track(sessionID: String) {}"
        ])

        #expect(issues.count == 1)
    }

    /// Case-insensitive match: `IdempotencyKey` matches an `idempotencyKey` position.
    @Test
    func caseInsensitiveNameMatchFlags() {
        let issues = analyze(files: [
            "Key.swift": "struct IdempotencyKey { let value: String }",
            "Use.swift": "struct Box { let IdempotencyKey: String }"
        ])

        #expect(issues.count == 1)
    }
}
