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

    @Test("a register-by-name run still fires — registration verbs count even with string args")
    func flagsRegisterByNameRun() {
        // `register` is unambiguous, so a register-by-name registry is still a hand-maintained
        // list even though its arguments are strings. Only the collection verbs get the
        // output-building exclusion.
        let source = """
        func setup() {
            commands.register("build")
            commands.register("test")
            commands.register("run")
            commands.register("clean")
            commands.register("lint")
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test("an append run of non-string items still fires")
    func flagsEntityAppendRun() {
        let source = """
        func collect() {
            handlers.append(FetchHandler())
            handlers.append(ParseHandler())
            handlers.append(ValidateHandler())
            handlers.append(PersistHandler())
            handlers.append(NotifyHandler())
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Does not fire

    @Test("an output-building append run of string text is not flagged")
    func outputBuildingAppendIgnored() {
        // The dominant false positive: a renderer/emitter building a report line by line. Each
        // append is unique text joined later, not a distinct component that can be silently
        // omitted from a registry.
        let source = #"""
        func render() -> String {
            var lines: [String] = []
            lines.append("Header")
            lines.append("")
            lines.append("  • item one")
            lines.append("  • item two  \(count)")
            lines.append("Footer")
            return lines.joined(separator: "\n")
        }
        """#
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

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
