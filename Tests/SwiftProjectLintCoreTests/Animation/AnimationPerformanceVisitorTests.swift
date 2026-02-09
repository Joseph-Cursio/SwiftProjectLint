import XCTest
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

final class AnimationPerformanceVisitorTests: XCTestCase {

    private func makeVisitor() -> AnimationPerformanceVisitor {
        let pattern = AnimationPerformancePatternRegistrar().pattern
        return AnimationPerformanceVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: AnimationPerformanceVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Excessive Spring Animations

    func testDetectsExcessiveSpringAnimations() throws {
        let source = """
        import SwiftUI

        struct AnimatedView: View {
            @State private var a = false
            @State private var b = false
            @State private var c = false
            @State private var d = false

            var body: some View {
                VStack {
                    Text("1").animation(.spring(), value: a)
                    Text("2").animation(.spring(), value: b)
                    Text("3").animation(.spring(), value: c)
                    Text("4").animation(.spring(), value: d)
                }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        XCTAssertEqual(visitor.detectedIssues.count, 1)

        let issue = try XCTUnwrap(visitor.detectedIssues.first)
        XCTAssertEqual(issue.ruleName, .excessiveSpringAnimations)
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertTrue(issue.message.contains("AnimatedView"))
        XCTAssertTrue(issue.message.contains("4"))
    }

    func testAllowsThreeOrFewerSpringAnimations() {
        let source = """
        import SwiftUI

        struct ModerateView: View {
            @State private var a = false
            @State private var b = false
            @State private var c = false

            var body: some View {
                VStack {
                    Text("1").animation(.spring(), value: a)
                    Text("2").animation(.spring(), value: b)
                    Text("3").animation(.spring(), value: c)
                }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        XCTAssertTrue(visitor.detectedIssues.isEmpty)
    }

    func testCountResetsPerStruct() {
        let source = """
        import SwiftUI

        struct ViewA: View {
            @State private var a = false
            @State private var b = false

            var body: some View {
                VStack {
                    Text("1").animation(.spring(), value: a)
                    Text("2").animation(.spring(), value: b)
                }
            }
        }

        struct ViewB: View {
            @State private var c = false
            @State private var d = false

            var body: some View {
                VStack {
                    Text("3").animation(.spring(), value: c)
                    Text("4").animation(.spring(), value: d)
                }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        XCTAssertTrue(visitor.detectedIssues.isEmpty)
    }

    func testDetectsSpringWithParameters() throws {
        let source = """
        import SwiftUI

        struct ParameterizedView: View {
            @State private var a = false
            @State private var b = false
            @State private var c = false
            @State private var d = false

            var body: some View {
                VStack {
                    Text("1").animation(.spring(response: 0.5, dampingFraction: 0.8), value: a)
                    Text("2").animation(.spring(response: 0.3, dampingFraction: 0.6), value: b)
                    Text("3").animation(.spring(duration: 0.4, bounce: 0.2), value: c)
                    Text("4").animation(.spring(), value: d)
                }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        XCTAssertEqual(visitor.detectedIssues.count, 1)

        let issue = try XCTUnwrap(visitor.detectedIssues.first)
        XCTAssertEqual(issue.ruleName, .excessiveSpringAnimations)
    }

    func testIgnoresNonSpringAnimations() {
        let source = """
        import SwiftUI

        struct EaseView: View {
            @State private var a = false
            @State private var b = false
            @State private var c = false
            @State private var d = false

            var body: some View {
                VStack {
                    Text("1").animation(.easeIn, value: a)
                    Text("2").animation(.easeOut, value: b)
                    Text("3").animation(.linear, value: c)
                    Text("4").animation(.default, value: d)
                }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        XCTAssertTrue(visitor.detectedIssues.isEmpty)
    }
}
