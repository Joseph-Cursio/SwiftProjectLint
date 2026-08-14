@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Three rules that should stand down when a name is in the implementation domain.
///
/// A leading underscore is Swift's convention for "this is not the interface" — a private
/// stored property behind a computed one, a library's own SPI, a storage companion. Rules
/// about *reaching past a public interface* or *co-locating unrelated types* are asking a
/// question the underscore has already answered.
///
/// Every case asserting absence is paired with a control that differs only in the
/// underscore or the shared word, since a rule that had stopped firing would satisfy the
/// absence just as well.
@Suite
struct ImplementationDetailNamingTests {

    // MARK: - Law of Demeter

    private func demeterIssues(_ source: String) -> [LintIssue] {
        let visitor = LawOfDemeterVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "TestFile.swift", tree: syntax)
        )
        visitor.setFilePath("TestFile.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    @Test("a chain rooted at an underscored identifier is not a Demeter violation")
    func underscoreRootedChainIsExempt() {
        let issues = demeterIssues("""
        struct Buffer {
            func count() -> Int { _storage.buffer.header.count }
        }
        """)

        #expect(issues.contains { $0.ruleName == .lawOfDemeter } == false)
    }

    /// Control: the same chain shape without the underscore is still a violation, so the
    /// exemption is the underscore's doing rather than the chain being too short.
    @Test("control — the same chain shape without an underscore still fires")
    func plainRootedChainStillFires() {
        let issues = demeterIssues("""
        struct Buffer {
            func count() -> Int { storage.buffer.header.count }
        }
        """)

        #expect(issues.contains { $0.ruleName == .lawOfDemeter })
    }

    // MARK: - Accessing implementation details

    private func implDetailIssues(_ source: String) -> [LintIssue] {
        let visitor = AccessingImplementationDetailsVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "TestFile.swift", tree: syntax)
        )
        visitor.setFilePath("TestFile.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    @Test("_base._member is not an implementation-detail access")
    func underscoredBaseIsExempt() {
        let issues = implDetailIssues("""
        struct Reader {
            func read() -> Int { _base._member }
        }
        """)

        #expect(issues.contains { $0.ruleName == .accessingImplementationDetails } == false)
    }

    /// Control: the same underscored *member* on an ordinary base still fires — that is a
    /// caller reaching past someone else's interface, which is what the rule is for.
    @Test("control — an underscored member on an ordinary base still fires")
    func plainBaseStillFires() {
        let issues = implDetailIssues("""
        struct Reader {
            func read() -> Int { service._member }
        }
        """)

        #expect(issues.contains { $0.ruleName == .accessingImplementationDetails })
    }

    // MARK: - Multiple types per file

    private func multipleTypesIssues(_ source: String, filePath: String) -> [LintIssue] {
        let visitor = MultipleTypesPerFileVisitor(pattern: MultipleTypesPerFile().pattern)
        visitor.setFilePath(filePath)
        visitor.walk(Parser.parse(source: source))
        return visitor.detectedIssues
    }

    @Test("an underscored companion type is not asked to move to its own file")
    func underscoredCompanionIsExempt() {
        let issues = multipleTypesIssues("""
        struct BridgingBuffer {
            let capacity: Int
        }

        final class __BridgingBufferStorage {
            var count: Int = 0
        }
        """, filePath: "BridgingBuffer.swift")

        #expect(issues.contains { $0.message.contains("__BridgingBufferStorage") } == false)
    }

    /// Control: an unrelated second type in the same file is still flagged, so the
    /// exemption above is not the rule having gone quiet.
    @Test("control — an unrelated second type is still flagged")
    func unrelatedSecondTypeStillFlagged() {
        let issues = multipleTypesIssues("""
        struct BridgingBuffer {
            let capacity: Int
        }

        final class SortOption {
            var count: Int = 0
        }
        """, filePath: "BridgingBuffer.swift")

        #expect(issues.contains { $0.message.contains("SortOption") })
    }

    /// A related name is often a *rearrangement* rather than an extension, which the
    /// longest-common-prefix test cannot see: `RuleDocumentationParser` and
    /// `ParsedRuleDocumentation` share no prefix at all.
    @Test("a type sharing a significant word with the file is coupled")
    func sharedWordIsCoupled() {
        let issues = multipleTypesIssues("""
        struct RuleDocumentationParser {
            func parse() -> Int { 0 }
        }

        struct ParsedRuleDocumentation {
            let text: String
        }
        """, filePath: "RuleDocumentationParser.swift")

        #expect(issues.contains { $0.message.contains("ParsedRuleDocumentation") } == false)
    }

    /// Control for the word test: a short shared fragment must not couple everything to
    /// everything. "Rule" is four characters and does couple; "Set" would not.
    @Test("control — a type sharing only a short fragment is still flagged")
    func shortFragmentIsNotCoupling() {
        let issues = multipleTypesIssues("""
        struct RuleDocumentationParser {
            func parse() -> Int { 0 }
        }

        struct TabView {
            let index: Int
        }
        """, filePath: "RuleDocumentationParser.swift")

        #expect(issues.contains { $0.message.contains("TabView") })
    }
}
