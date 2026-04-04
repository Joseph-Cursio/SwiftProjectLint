import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

struct FormatterInViewBodyCalendarLocaleTests {

    private func makeVisitor() -> FormatterInViewBodyVisitor {
        let pattern = FormatterInViewBody().pattern
        return FormatterInViewBodyVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: FormatterInViewBodyVisitor, source: String) {
        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
    }

    // MARK: - Calendar.current and Locale.current

    @Test("Detects Calendar.current in body")
    func detectsCalendarCurrentInBody() throws {
        let source = """
        struct EventRow: View {
            var body: some View {
                let cal = Calendar.current
                Text("hi")
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .formatterInViewBody)
        #expect(issue.message.contains("Calendar.current"))
    }

    @Test("Detects Locale.current in body")
    func detectsLocaleCurrentInBody() throws {
        let source = """
        struct PriceView: View {
            var body: some View {
                let locale = Locale.current
                Text("hi")
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("Locale.current"))
    }

    @Test("Detects Calendar.current and a formatter together")
    func detectsCalendarAndFormatterTogether() {
        let source = """
        struct MyView: View {
            var body: some View {
                let cal = Calendar.current
                let fmt = DateFormatter()
                Text("hi")
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 2)
    }

    @Test("No issue for Calendar.current outside view body")
    func noIssueForCalendarCurrentOutsideBody() {
        let source = """
        class Helper {
            func makeDate() -> Date {
                Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for Calendar.current in a non-View struct body property")
    func noIssueForCalendarCurrentInNonViewStruct() {
        let source = """
        struct Config {
            var body: String {
                let cal = Calendar.current
                return cal.identifier.debugDescription
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for Calendar accessed via environment")
    func noIssueForCalendarViaEnvironment() {
        let source = """
        struct EventRow: View {
            @Environment(\\.calendar) var calendar

            var body: some View {
                Text("hi")
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}
