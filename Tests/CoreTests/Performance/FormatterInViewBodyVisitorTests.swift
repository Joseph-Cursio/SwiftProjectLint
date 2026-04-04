import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct FormatterInViewBodyVisitorTests {

    private func makeVisitor() -> FormatterInViewBodyVisitor {
        let pattern = FormatterInViewBody().pattern
        return FormatterInViewBodyVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: FormatterInViewBodyVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Flagged Formatter Types

    @Test
    func detectsDateFormatterInBody() throws {
        let source = """
        struct EventRow: View {
            var body: some View {
                let formatter = DateFormatter()
                Text("hi")
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .formatterInViewBody)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("DateFormatter"))
    }

    @Test("All nine formatter types are detected", arguments: [
        ("NumberFormatter", "struct V: View { var body: some View { let f = NumberFormatter() } }"),
        ("ISO8601DateFormatter", "struct V: View { var body: some View { let f = ISO8601DateFormatter() } }"),
        ("DateComponentsFormatter", "struct V: View { var body: some View { let f = DateComponentsFormatter() } }"),
        ("ByteCountFormatter", "struct V: View { var body: some View { let f = ByteCountFormatter() } }"),
        ("MeasurementFormatter", "struct V: View { var body: some View { let f = MeasurementFormatter() } }"),
        ("PersonNameComponentsFormatter", "struct V: View { var body: some View { let f = PersonNameComponentsFormatter() } }"),
        ("JSONDecoder", "struct V: View { var body: some View { let d = JSONDecoder() } }"),
        ("JSONEncoder", "struct V: View { var body: some View { let e = JSONEncoder() } }")
    ])
    func detectsFormatterType(typeName: String, source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues.first?.message.contains(typeName) == true)
    }

    @Test("Message contains the formatter type name")
    func messageContainsTypeName() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                let f = JSONDecoder()
                Text("x")
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("JSONDecoder"))
    }

    @Test("Flags multiple formatters in the same body")
    func detectsMultipleFormattersInBody() {
        let source = """
        struct EventRow: View {
            var body: some View {
                let df = DateFormatter()
                let nf = NumberFormatter()
                Text("hi")
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 2)
    }

    @Test("Flags formatter nested inside a closure in body")
    func detectsFormatterInNestedClosure() {
        let source = """
        struct MyView: View {
            var body: some View {
                VStack {
                    let f = DateFormatter()
                    Text("hi")
                }
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Not Flagged

    @Test("No issue when formatter is a static stored property")
    func noIssueForStaticProperty() {
        let source = """
        struct EventRow: View {
            private static let formatter: DateFormatter = {
                let f = DateFormatter()
                f.dateStyle = .medium
                return f
            }()

            var body: some View {
                Text("hi")
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue when formatter is a stored instance property")
    func noIssueForStoredInstanceProperty() {
        let source = """
        struct EventRow: View {
            private let formatter = DateFormatter()

            var body: some View {
                Text("hi")
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue when formatter is created outside of View body")
    func noIssueForFormatterOutsideViewBody() {
        let source = """
        class DataService {
            func makeFormatter() -> DateFormatter {
                return DateFormatter()
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for non-View struct with body property")
    func noIssueForNonViewStruct() {
        let source = """
        struct Request {
            var body: Data {
                let encoder = JSONEncoder()
                return encoder.encode("test") ?? Data()
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue when formatter is used but not instantiated in body")
    func noIssueWhenFormatterPassedIn() {
        let source = """
        struct EventRow: View {
            let formatter: DateFormatter

            var body: some View {
                Text(formatter.string(from: Date()))
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for lightweight value-type format styles")
    func noIssueForFormatStyle() {
        let source = """
        struct EventRow: View {
            var body: some View {
                Text(Date.now.formatted(.dateTime))
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Multiple Views in Source

    @Test("Only flags formatter inside the View body, not a sibling helper")
    func onlyFlagsInsideViewBody() {
        let source = """
        struct MyView: View {
            func makeFormatter() -> DateFormatter {
                DateFormatter()
            }

            var body: some View {
                let bad = DateFormatter()
                Text("hi")
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test("Handles multiple views in one file independently")
    func handlesMultipleViewsInFile() {
        let source = """
        struct SafeView: View {
            private static let formatter = DateFormatter()
            var body: some View { Text("ok") }
        }

        struct UnsafeView: View {
            var body: some View {
                let f = DateFormatter()
                Text("bad")
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues[0].message.contains("DateFormatter"))
    }
}
