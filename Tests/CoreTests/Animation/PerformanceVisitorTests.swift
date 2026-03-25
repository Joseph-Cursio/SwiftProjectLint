import Testing
@testable import Core
import SwiftSyntax
import SwiftParser

struct PerformanceVisitorTests {

    private func makeVisitor(for rule: RuleIdentifier = .excessiveSpringAnimations) throws -> AnimationPerformanceVisitor {
        let patterns = AnimationPerformance().patterns
        let pattern = try #require(patterns.first { $0.name == rule })
        return AnimationPerformanceVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: AnimationPerformanceVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Excessive Spring Animations

    @Test
    func detectsExcessiveSpringAnimations() throws {
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

        let visitor = try makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .excessiveSpringAnimations)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("AnimatedView"))
        #expect(issue.message.contains("4"))
    }

    // swiftprojectlint:disable Test Missing Require
    @Test
    func allowsThreeOrFewerSpringAnimations() throws {
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

        let visitor = try makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func countResetsPerStruct() throws {
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

        let visitor = try makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func detectsSpringWithParameters() throws {
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

        let visitor = try makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .excessiveSpringAnimations)
    }

    @Test
    func ignoresNonSpringAnimations() throws {
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

        let visitor = try makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Animation in High-Frequency Update

    @Test
    func detectsAnimationInOnReceiveContext() throws {
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

        let visitor = try makeVisitor(for: .animationInHighFrequencyUpdate)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .animationInHighFrequencyUpdate)
        #expect(issue.severity == .warning)
    }

    @Test
    func detectsAnimationInOnChangeContext() throws {
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

        let visitor = try makeVisitor(for: .animationInHighFrequencyUpdate)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .animationInHighFrequencyUpdate)
    }

    @Test
    func allowsAnimationOutsideHighFrequencyContext() throws {
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

        let visitor = try makeVisitor(for: .animationInHighFrequencyUpdate)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Long Animation Duration

    @Test
    func detectsLongAnimationDuration() throws {
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

        let visitor = try makeVisitor(for: .longAnimationDuration)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .longAnimationDuration)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("3.0"))
    }

    @Test
    func detectsLongSpringDuration() throws {
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

        let visitor = try makeVisitor(for: .longAnimationDuration)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .longAnimationDuration)
        #expect(issue.message.contains("5.0"))
    }

    @Test
    func allowsNormalAnimationDuration() throws {
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

        let visitor = try makeVisitor(for: .longAnimationDuration)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func allowsExactlyTwoSecondDuration() throws {
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

        let visitor = try makeVisitor(for: .longAnimationDuration)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
