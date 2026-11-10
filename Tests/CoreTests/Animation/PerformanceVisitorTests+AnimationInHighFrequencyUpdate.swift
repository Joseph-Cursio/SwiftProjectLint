@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

extension PerformanceVisitorTests {
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
