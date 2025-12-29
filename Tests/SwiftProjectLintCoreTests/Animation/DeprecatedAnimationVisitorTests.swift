import XCTest
@testable import SwiftProjectLintCore
import SwiftSyntax

final class DeprecatedAnimationVisitorTests: XCTestCase {

    private func makeVisitor() -> DeprecatedAnimationVisitor {
        let pattern = DeprecatedAnimationPatternRegistrar().pattern
        return DeprecatedAnimationVisitor(pattern: pattern)
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
        try visitor.run(source: source)

        XCTAssertEqual(visitor.issues.count, 1)

        let issue = try XCTUnwrap(visitor.issues.first)
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
        try visitor.run(source: source)

        XCTAssertTrue(visitor.issues.isEmpty)
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
        try visitor.run(source: source)

        XCTAssertTrue(visitor.issues.isEmpty)
    }
}
