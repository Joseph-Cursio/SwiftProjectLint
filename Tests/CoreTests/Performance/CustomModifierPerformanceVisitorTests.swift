import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct CustomModifierPerformanceVisitorTests {

    private func makeVisitor() -> CustomModifierPerformanceVisitor {
        let pattern = CustomModifierPerformance().pattern
        return CustomModifierPerformanceVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: CustomModifierPerformanceVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    @Test
    func sortedInModifierBodyFlags() {
        let source = """
        import SwiftUI

        struct ListModifier: ViewModifier {
            let items: [String]

            func body(content: Content) -> some View {
                VStack {
                    ForEach(items.sorted(), id: \\.self) { item in
                        Text(item)
                    }
                    content
                }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues.first?.ruleName == .customModifierPerformance)
    }

    @Test
    func filterInModifierBodyFlags() {
        let source = """
        import SwiftUI

        struct FilterModifier: ViewModifier {
            let items: [String]

            func body(content: Content) -> some View {
                let filtered = items.filter { !$0.isEmpty }
                VStack {
                    ForEach(filtered, id: \\.self) { Text($0) }
                    content
                }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func simpleModifierClean() {
        let source = """
        import SwiftUI

        struct SimpleModifier: ViewModifier {
            let color: Color

            func body(content: Content) -> some View {
                content
                    .padding()
                    .background(color)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func regularStructNotFlagged() {
        let source = """
        import Foundation

        struct DataProcessor {
            let items: [String]

            func process() -> [String] {
                return items.sorted()
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func expensiveOpInHelperNotFlagged() {
        let source = """
        import SwiftUI

        struct HelperModifier: ViewModifier {
            let items: [String]

            private var sortedItems: [String] {
                items.sorted()
            }

            func body(content: Content) -> some View {
                VStack {
                    ForEach(sortedItems, id: \\.self) { Text($0) }
                    content
                }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func multipleExpensiveOpsFlags() {
        let source = """
        import SwiftUI

        struct HeavyModifier: ViewModifier {
            let items: [Int]

            func body(content: Content) -> some View {
                let processed = items.filter { $0 > 0 }.sorted()
                VStack {
                    ForEach(processed, id: \\.self) { Text("\\($0)") }
                    content
                }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }
}
