@testable import Core
import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

private func shadowingIssues(_ source: String) -> [LintIssue] {
    let visitor = VariableShadowingVisitor(pattern: VariableShadowing().pattern)
    visitor.walk(Parser.parse(source: source))
    return visitor.detectedIssues
}

/// The rebinding exemption (`let x = x.cleaned()`, `for x in x`) asks whether the initializer uses
/// the outer name. It used to ask whether the outer name's *spelling* appears there, so a key-path
/// component or another value's member of the same name exempted a shadow that never reads the
/// outer binding.
@Suite("Variable Shadowing — key paths and members are not rebindings")
struct VariableShadowingKeyPathTests {

    // MARK: - Reported: the outer name is never read

    @Test("a key-path component is not a use of the outer name")
    func keyPathComponentDoesNotExemptTheShadow() throws {
        let issues = shadowingIssues("""
        func summarize(_ orders: [Order]) {
            let total = 0
            do {
                let total = orders.map(\\.total).reduce(0, +)
                print(total)
            }
            print(total)
        }
        """)
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("'total'"))
    }

    @Test("a member or an argument label is not a use of the outer name", arguments: [
        "let total = orders.first?.total ?? 0",
        "let total = price(total: orders.count)"
    ])
    func sameSpellingDoesNotExemptTheShadow(declaration: String) {
        let issues = shadowingIssues("""
        func summarize(_ orders: [Order]) {
            let total = 0
            do {
                \(declaration)
                print(total)
            }
            print(total)
        }
        """)
        #expect(issues.count == 1)
    }

    @Test("the closure spelling was always reported")
    func closureSpellingIsReported() {
        let issues = shadowingIssues("""
        func summarize(_ orders: [Order]) {
            let total = 0
            do {
                let total = orders.map { o in o.amount }.reduce(0, +)
                print(total)
            }
            print(total)
        }
        """)
        #expect(issues.count == 1)
    }

    @Test("a loop over a key path is not `for x in x`")
    func loopOverKeyPathDoesNotExemptTheShadow() {
        let issues = shadowingIssues("""
        func summarize(_ orders: [Order]) {
            let total = 0
            for total in orders.map(\\.total) {
                print(total)
            }
            print(total)
        }
        """)
        #expect(issues.count == 1)
    }

    // MARK: - Exempt: the outer name is read

    @Test("a genuine rebinding is still exempt", arguments: [
        "let total = total + orders.count",
        "let total = rows.map(\\.[total]).count",
        // A capture list names the outer binding bare: `[total]` captures it.
        "let total = { [total] in run() }",
        "let total = { [weak total] in run() }"
    ])
    func genuineRebindingIsExempt(rebinding: String) {
        let issues = shadowingIssues("""
        func summarize(_ orders: [Order], _ rows: [[Int]]) {
            let total = 0
            do {
                \(rebinding)
                print(total)
            }
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test("`for x in x.children` is still exempt")
    func loopOverTheOuterNameIsExempt() {
        let issues = shadowingIssues("""
        func walk(_ root: Node) {
            let node = root
            do {
                for node in node.children {
                    print(node)
                }
            }
        }
        """)
        #expect(issues.isEmpty)
    }
}
