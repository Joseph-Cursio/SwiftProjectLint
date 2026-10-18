@testable import Core
import Testing

/// When an index in a loop visits every position, which compares a whole sequence, and when the
/// loop narrows it to one position after all.
@Suite
struct PositionalViewLookupLoopTests {

    private func analyzeTest(_ statements: String) -> [LintIssue] {
        positionalViewLookupIssues(inTestBody: statements)
    }

    @Test("every-position loops written with forEach, reversed, startIndex, min, a count local or a capture")
    func everyPositionSpellings() {
        let issues = analyzeTest("""
            let rows = try sut.inspect().findAll(ViewType.Text.self)
            let stack = try sut.inspect().find(ViewType.VStack.self)
            expected.enumerated().forEach { index, name in _ = try? stack.text(index).string() == name }
            zip(rows.indices, expected).forEach { index, name in _ = try? rows[index].string() == name }
            for index in rows.indices.reversed() { _ = try rows[index] }
            for index in rows.startIndex..<rows.endIndex { _ = try rows[index] }
            for index in 0..<min(rows.count, expected.count) { _ = try rows[index] }
            let count = expected.count
            for index in 0..<count { _ = try rows[index] }
            for index in rows.indices { DispatchQueue.main.async { [index = index] in _ = try? stack.text(index) } }
            for index in 0...(rows.count - 1) { _ = try rows[index] }
            zip(0..., expected).forEach { index, name in _ = try? stack.text(index).string() == name }
            for (index, name) in zip(0..., expected) { _ = try stack.text(index).string() == name }
        """)
        #expect(issues.isEmpty)
    }

    @Test("a condition on the data keeps the exemption; guard and switch on the index narrow it")
    func narrowing() {
        let issues = analyzeTest("""
            let rows = try sut.inspect().findAll(ViewType.Text.self)
            for index in rows.indices { if expected[index] == "b" { _ = try rows[index] } }
            for index in rows.indices { guard index == 1 else { continue }; _ = try rows[index] }
            for index in rows.indices { switch index { case 1: _ = try rows[index]; default: break } }
        """)
        #expect(issues.map(\.lineNumber) == [7, 8])
    }

    @Test("narrowing in parentheses, as a pattern, or as a filter that skips the rest of the body")
    func narrowingSpellings() {
        let issues = analyzeTest("""
            let rows = try sut.inspect().findAll(ViewType.Text.self)
            for index in rows.indices { if (index == 1) { _ = try rows[index] } }
            for index in rows.indices { guard (index == 1) else { continue }; _ = try rows[index] }
            for index in rows.indices { if case 1 = index { _ = try rows[index] } }
            for index in rows.indices { if index == 0 { continue }; _ = try rows[index] }
            for index in rows.indices { guard index > 0 else { continue }; _ = try rows[index] }
            for index in rows.indices { if index > 0 { _ = try rows[index] } else { break } }
            for index in rows.indices { if index != 0 { _ = try rows[index] } }
            for index in rows.indices { if expected[index] == "b" { continue }; _ = try rows[index] }
            for index in rows.indices { if index < 2 { print(index) }; _ = try rows[index] }
        """)
        #expect(issues.map(\.lineNumber) == [6, 7, 8, 9, 10, 11, 12])
    }

    @Test("skipFound with a loop's index over every position is exempt, as findAll(…)[index] is")
    func skipFoundOverEveryPosition() {
        let issues = analyzeTest("""
            for index in expected.indices { _ = try sut.inspect().find(ViewType.Text.self, skipFound: index) }
            for index in 0..<3 { _ = try sut.inspect().find(ViewType.Text.self, skipFound: index) }
            for index in expected.indices where index > 0 { _ = try sut.inspect().find(text: "a", skipFound: index) }
        """)
        #expect(issues.map(\.lineNumber) == [6, 7])
    }
}
