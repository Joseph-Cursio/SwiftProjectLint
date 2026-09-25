@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// `StateVariable.lineNumber` must be the line the declaration starts on, whatever
/// the source's encoding or line endings.
///
/// Positions in a syntax tree are UTF-8 byte offsets. Counting them as `Character`s
/// over-reads the source whenever anything before the node is wider than one byte
/// (non-ASCII text, and CRLF, which is one `Character` but two bytes). Splitting on
/// `.newlines` then counts a CRLF as two line breaks.
@Suite("StateVariableVisitor line numbers")
struct StateVariableVisitorLineNumberTests {

    private func lineNumbers(in source: String) -> [String: Int] {
        let visitor = makeStateVariableVisitor(for: source)
        return Dictionary(uniqueKeysWithValues: visitor.stateVariables.map { ($0.name, $0.lineNumber) })
    }

    @Test("reports declaration lines in ASCII source")
    func asciiSource() {
        let source = """
        struct TestView: View {
            @State private var count = 0
            @State private var name = ""
            var body: some View { Text("Test") }
        }
        """

        #expect(lineNumbers(in: source) == ["count": 2, "name": 3])
    }

    @Test("reports declaration lines after multi-byte characters")
    func multiByteCharactersBeforeDeclaration() {
        let source = """
        // Café naïve résumé — 🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉
        struct TestView: View {
            @State private var count = 0

            @State private var name = ""
            var body: some View { Text("Test") }
        }
        """

        #expect(lineNumbers(in: source) == ["count": 3, "name": 5])
    }

    @Test("reports declaration lines in CRLF source")
    func crlfLineEndings() {
        let source = [
            "struct TestView: View {",
            "    @State private var count = 0",
            "    @State private var name = \"\"",
            "    var body: some View { Text(\"Test\") }",
            "}"
        ].joined(separator: "\r\n")

        #expect(lineNumbers(in: source) == ["count": 2, "name": 3])
    }
}
