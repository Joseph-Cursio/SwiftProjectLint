import XCTest
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

final class DeprecatedAnimationVisitorTests: XCTestCase {

    private func makeVisitor() -> DeprecatedAnimationVisitor {
        let pattern = DeprecatedAnimationPatternRegistrar().pattern
        return DeprecatedAnimationVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: DeprecatedAnimationVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    func testDeprecatedAnimationModifier() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello, World!")
                    .animation(.default)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        XCTAssertEqual(visitor.detectedIssues.count, 1)

        let issue = try XCTUnwrap(visitor.detectedIssues.first)
        XCTAssertEqual(issue.ruleName, .deprecatedAnimation)
        XCTAssertEqual(issue.severity, .warning)
    }

    func testModernAnimationModifier() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            @State private var didChange = false
            var body: some View {
                Text("Hello, World!")
                    .animation(.default, value: didChange)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        XCTAssertTrue(visitor.detectedIssues.isEmpty)
    }

    func testBindingAnimationModifier() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            @State private var didChange = false
            var body: some View {
                let textBinding = Binding(get: { "Hello" }, set: { _ in })
                TextField("Title", text: textBinding.animation())
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        XCTAssertTrue(visitor.detectedIssues.isEmpty)
    }
}
