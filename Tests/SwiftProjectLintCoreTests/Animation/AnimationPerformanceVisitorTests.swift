import XCTest
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

final class AnimationPerformanceVisitorTests: XCTestCase {

    private func makeVisitor(for rule: RuleIdentifier = .excessiveSpringAnimations) -> AnimationPerformanceVisitor {
        let patterns = AnimationPerformancePatternRegistrar().patterns
        // swiftlint:disable:next force_unwrapping
        let pattern = patterns.first { $0.name == rule }!
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

    // MARK: - Animation in High-Frequency Update

    func testDetectsAnimationInOnReceiveContext() throws {
        let source = """
        import SwiftUI

        struct TimerView: View {
            let timer = Timer.publish(every: 1, on: .main, in: .common)
            @State private var count = 0

            var body: some View {
                Text("\\(count)")
                    .onReceive(timer) { _ in count += 1 }
                    .animation(.spring(), value: count)
            }
        }
        """

        let visitor = makeVisitor(for: .animationInHighFrequencyUpdate)
        runVisitor(visitor, source: source)

        XCTAssertEqual(visitor.detectedIssues.count, 1)

        let issue = try XCTUnwrap(visitor.detectedIssues.first)
        XCTAssertEqual(issue.ruleName, .animationInHighFrequencyUpdate)
        XCTAssertEqual(issue.severity, .warning)
    }

    func testDetectsAnimationInOnChangeContext() throws {
        let source = """
        import SwiftUI

        struct ChangeView: View {
            @State private var value = ""
            @State private var isEditing = false

            var body: some View {
                TextField("Input", text: $value)
                    .onChange(of: value) { isEditing = true }
                    .animation(.easeIn, value: isEditing)
            }
        }
        """

        let visitor = makeVisitor(for: .animationInHighFrequencyUpdate)
        runVisitor(visitor, source: source)

        XCTAssertEqual(visitor.detectedIssues.count, 1)

        let issue = try XCTUnwrap(visitor.detectedIssues.first)
        XCTAssertEqual(issue.ruleName, .animationInHighFrequencyUpdate)
    }

    func testAllowsAnimationOutsideHighFrequencyContext() {
        let source = """
        import SwiftUI

        struct NormalView: View {
            @State private var isVisible = false

            var body: some View {
                Text("Hello")
                    .opacity(isVisible ? 1 : 0)
                    .animation(.spring(), value: isVisible)
            }
        }
        """

        let visitor = makeVisitor(for: .animationInHighFrequencyUpdate)
        runVisitor(visitor, source: source)

        XCTAssertTrue(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Long Animation Duration

    func testDetectsLongAnimationDuration() throws {
        let source = """
        import SwiftUI

        struct SlowView: View {
            @State private var isVisible = false

            var body: some View {
                Text("Hello")
                    .animation(.easeIn(duration: 3.0), value: isVisible)
            }
        }
        """

        let visitor = makeVisitor(for: .longAnimationDuration)
        runVisitor(visitor, source: source)

        XCTAssertEqual(visitor.detectedIssues.count, 1)

        let issue = try XCTUnwrap(visitor.detectedIssues.first)
        XCTAssertEqual(issue.ruleName, .longAnimationDuration)
        XCTAssertEqual(issue.severity, .info)
        XCTAssertTrue(issue.message.contains("3.0"))
    }

    func testDetectsLongSpringDuration() throws {
        let source = """
        import SwiftUI

        struct SlowSpringView: View {
            @State private var isVisible = false

            var body: some View {
                Text("Hello")
                    .animation(.spring(duration: 5.0), value: isVisible)
            }
        }
        """

        let visitor = makeVisitor(for: .longAnimationDuration)
        runVisitor(visitor, source: source)

        XCTAssertEqual(visitor.detectedIssues.count, 1)

        let issue = try XCTUnwrap(visitor.detectedIssues.first)
        XCTAssertEqual(issue.ruleName, .longAnimationDuration)
        XCTAssertTrue(issue.message.contains("5.0"))
    }

    func testAllowsNormalAnimationDuration() {
        let source = """
        import SwiftUI

        struct NormalView: View {
            @State private var isVisible = false

            var body: some View {
                Text("Hello")
                    .animation(.easeIn(duration: 0.5), value: isVisible)
            }
        }
        """

        let visitor = makeVisitor(for: .longAnimationDuration)
        runVisitor(visitor, source: source)

        XCTAssertTrue(visitor.detectedIssues.isEmpty)
    }

    func testAllowsExactlyTwoSecondDuration() {
        let source = """
        import SwiftUI

        struct BoundaryView: View {
            @State private var isVisible = false

            var body: some View {
                Text("Hello")
                    .animation(.easeIn(duration: 2.0), value: isVisible)
            }
        }
        """

        let visitor = makeVisitor(for: .longAnimationDuration)
        runVisitor(visitor, source: source)

        XCTAssertTrue(visitor.detectedIssues.isEmpty)
    }
}
