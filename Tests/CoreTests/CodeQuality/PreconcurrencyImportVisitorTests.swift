@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct PreconcurrencyImportVisitorTests {

    private func analyze(_ source: String) -> [LintIssue] {
        let visitor = PreconcurrencyImportVisitor(pattern: PreconcurrencyImport().pattern)
        visitor.walk(Parser.parse(source: source))
        return visitor.detectedIssues.filter { $0.ruleName == .preconcurrencyImport }
    }

    @Test
    func flagsPreconcurrencyImport() throws {
        let issues = analyze("@preconcurrency import LegacyKit")
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.ruleName == .preconcurrencyImport)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("LegacyKit"))
    }

    @Test
    func flagsPreconcurrencyImportWithOtherAttributesAndModifiers() {
        // The annotation can co-occur with access modifiers / submodule paths.
        #expect(analyze("@preconcurrency public import LegacyKit.SubModule").count == 1)
    }

    @Test
    func ignoresPlainImport() {
        #expect(analyze("import Foundation").isEmpty)
    }

    @Test
    func ignoresOtherImportAttributes() {
        #expect(analyze("@testable import MyApp").isEmpty)
    }

    @Test
    func flagsEachPreconcurrencyImportSeparately() {
        let source = """
        @preconcurrency import LegacyA
        import Foundation
        @preconcurrency import LegacyB
        """
        #expect(analyze(source).count == 2)
    }
}
