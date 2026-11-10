@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct PerformanceVisitorStateTrackingTests {

    private func createVisitor() -> PerformanceVisitor {
        PerformanceVisitor(patternCategory: .performance)
    }

    @Test func testTracksStateVariableDeclaration() {
        let source = """
        struct TestView: View {
            @State private var count = 0
            @State private var name = "Test"

            var body: some View {
                Text("\\(count)")
            }
        }
        """

        let visitor = createVisitor()
        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)

        // State variables should be tracked
        #expect(visitor.stateVariables.isEmpty == false) // Should track @State variables
    }

    @Test func testStateVariableAssignmentTracking() {
        let source = """
        struct TestView: View {
            @State private var count = 0

            var body: some View {
                Button("Increment") {
                    count = count + 1
                }
            }
        }
        """

        let visitor = createVisitor()
        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)

        // Should process assignment without error
        #expect(visitor.stateVariables.isEmpty == false)
    }
}
