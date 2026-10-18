@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// How `ForEach Without ID` resolves an element type against the pre-scan's `Identifiable`
/// names: qualified element types, and collections reached through a type's static member.
@Suite
struct ForEachIdentifiableLookupTests {

    private func forEachWithoutIDLines(
        _ source: String,
        identifiableTypes: Set<String> = [],
        identifiableCollectionProperties: Set<String> = []
    ) -> [Int] {
        let visitor = PerformanceVisitor(patternCategory: .performance)
        visitor.knownIdentifiableTypes = identifiableTypes
        visitor.knownIdentifiableCollectionProperties = identifiableCollectionProperties
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: "View.swift", tree: syntax))
        visitor.setFilePath("View.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .forEachWithoutID }.map(\.lineNumber)
    }

    /// The pre-scan lists `Feed.Entry` (and its leaf, `Entry`); a qualified `[Other.Entry]`
    /// names a different type and must not borrow that conformance.
    @Test func qualifiedElementTypeMatchesOnlyItsOwnPath() {
        let source = """
        struct EntriesView: View {
            let entries: [Feed.Entry]
            let others: [Other.Entry]
            var body: some View {
                ForEach(entries) { entry in Text("e") }
                ForEach(others) { other in Text("o") }
            }
        }
        """
        #expect(forEachWithoutIDLines(source, identifiableTypes: ["Entry", "Feed.Entry"]) == [6])
    }

    /// `ForEach(PreviewData.insights)`: the inference guesses the uppercase base, `PreviewData`,
    /// which is not Identifiable; the catalog still knows `insights` is an array of one.
    @Test func staticMemberOfANonIdentifiableTypeConsultsTheCatalog() {
        let source = """
        struct PreviewView: View {
            var body: some View {
                ForEach(PreviewData.insights) { insight in Text("i") }
                ForEach(PreviewData.names) { name in Text(name) }
            }
        }
        """
        let lines = forEachWithoutIDLines(
            source, identifiableTypes: ["Insight"], identifiableCollectionProperties: ["insights"]
        )
        #expect(lines == [4])
    }
}
