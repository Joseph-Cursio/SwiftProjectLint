import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct OnReceiveWithoutDebounceVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = OnReceiveWithoutDebounceVisitor(patternCategory: .performance)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .onReceiveWithoutDebounce }
    }

    // MARK: - Positive: flags high-frequency onReceive without rate limiting

    @Test func testFlagsSubSecondTimerWithoutDebounce() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .onReceive(Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()) { _ in
                        updatePosition()
                    }
            }
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("rate limiting"))
    }

    @Test func testFlagsNotificationCenterWithoutDebounce() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .onReceive(NotificationCenter.default.publisher(for: .someNotification)) { _ in
                        refresh()
                    }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsHalfSecondTimer() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                        tick()
                    }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testAllowsTimerAtOneSecond() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
                        updateClock()
                    }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testAllowsDebounced() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .onReceive(
                        Timer.publish(every: 0.1, on: .main, in: .common)
                            .autoconnect()
                            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
                    ) { _ in
                        update()
                    }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testAllowsThrottled() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .onReceive(
                        NotificationCenter.default.publisher(for: .someNotification)
                            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
                    ) { _ in
                        refresh()
                    }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForNonHighFrequencyPublisher() throws {
        let source = """
        struct MyView: View {
            @Published var searchText = ""
            var body: some View {
                Text("Hello")
                    .onReceive(Just("test")) { value in
                        handle(value)
                    }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForUnrelatedModifiers() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .padding()
                    .font(.title)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}
