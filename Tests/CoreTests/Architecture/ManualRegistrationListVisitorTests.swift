@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// The "mismatched lists → registry" rule. Fires on a *hand-maintained
/// registration list*: a run of consecutive statements that each call the same
/// registration-verb method (`register…`/`add…`/`append`/`record`) — the shape
/// where a new entry (a template, a category, a factory) can be added elsewhere
/// and silently omitted here, with no compile error. The fix is a data-driven
/// registry: one declared array iterated once.
@Suite
struct ManualRegistrationListVisitorTests {

    private func makeVisitor() -> ManualRegistrationListVisitor {
        ManualRegistrationListVisitor(pattern: ManualRegistrationList().pattern)
    }

    private func runVisitor(_ visitor: ManualRegistrationListVisitor, source: String) {
        visitor.walk(Parser.parse(source: source))
    }

    // MARK: - Fires

    @Test("a run of 5 identical registration calls is flagged once")
    func flagsRegistrationRun() throws {
        let source = """
        func registerAll() {
            SourcePatternRegistry.registerFactory { StateManagement() }
            SourcePatternRegistry.registerFactory { Performance() }
            SourcePatternRegistry.registerFactory { Security() }
            SourcePatternRegistry.registerFactory { Accessibility() }
            SourcePatternRegistry.registerFactory { Modernization() }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .manualRegistrationList)
        #expect(issue.severity == .info)
    }

    @Test("an append/record run is flagged (camelCase-boundary verb match)")
    func flagsAppendRun() {
        let source = """
        func collect() {
            collector.record(partition)
            collector.record(comparator)
            collector.record(predicate)
            collector.record(involution)
            collector.record(filterSubset)
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Does not fire

    @Test("a short run (below threshold) is not flagged")
    func shortRunIgnored() {
        let source = """
        func setup() {
            registry.register(a)
            registry.register(b)
            registry.register(c)
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("a run of the same NON-registration method is not flagged")
    func nonRegistrationVerbIgnored() {
        let source = """
        func run() {
            printer.print(a)
            printer.print(b)
            printer.print(c)
            printer.print(d)
            printer.print(e)
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("`address`-style names do not match the `add` verb (camelCase boundary)")
    func addressIsNotAdd() {
        let source = """
        func run() {
            client.address(a)
            client.address(b)
            client.address(c)
            client.address(d)
            client.address(e)
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("interleaved different callees do not form a run")
    func mixedCalleesIgnored() {
        let source = """
        func mixed() {
            registry.register(a)
            other.append(b)
            registry.register(c)
            other.append(d)
            registry.register(e)
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}
