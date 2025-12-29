import XCTest
@testable import SwiftProjectLintCore
import SwiftSyntax

class AnimationVisitorTests: XCTestCase {

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

        let visitor = AnimationVisitor()
        try visitor.walk(sourceCode)
        let issues = visitor.issues

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.ruleName, .deprecatedAnimation)
        XCTAssertEqual(issues.first?.message, "Use of the deprecated `.animation()` modifier should be avoided.")
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

        let visitor = AnimationVisitor()
        try visitor.walk(sourceCode)
        let issues = visitor.issues

        XCTAssertTrue(issues.isEmpty)
    }
}
