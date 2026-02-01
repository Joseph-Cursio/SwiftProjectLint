import XCTest
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

class AnimationVisitorTests: XCTestCase {

    private func makeVisitor() -> DeprecatedAnimationVisitor {
        let pattern = DeprecatedAnimationPatternRegistrar().pattern
        return DeprecatedAnimationVisitor(pattern: pattern)
    }

    func testDeprecatedAnimationModifierDetection() throws {
        let sourceCode = """
        import SwiftUI

        struct MyView: View {
            @State private var isAnimating = false

            var body: some View {
                Text("Hello, World!")
                    .animation(.default)
                    .padding()
            }
        }
        """

        let visitor = makeVisitor()
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        let issues = visitor.detectedIssues

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.ruleName, .deprecatedAnimation)
    }

    func testModernAnimationModifierDoesNotTriggerIssue() throws {
        let sourceCode = """
        import SwiftUI

        struct MyView: View {
            @State private var isAnimating = false

            var body: some View {
                Text("Hello, World!")
                    .animation(.default, value: isAnimating)
                    .padding()
            }
        }
        """

        let visitor = makeVisitor()
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        let issues = visitor.detectedIssues

        XCTAssertTrue(issues.isEmpty)
    }
}
