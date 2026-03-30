import Testing
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

/// Coverage tests for uncovered paths in WithAnimationVisitor.swift:
/// - Default break case in pattern.name switch (line 32)
/// - perform: labeled argument extraction (lines 109-118)
/// - StateMutationChecker compound operator detection (line 139)
@Suite("WithAnimationVisitor Coverage Tests")
struct WithAnimationVisitorCoverageTests {

    private func makeVisitor(for rule: RuleIdentifier) throws -> WithAnimationVisitor {
        let patterns = WithAnimation().patterns
        let pattern = try #require(patterns.first { $0.name == rule })
        return WithAnimationVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: WithAnimationVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - perform: labeled argument (lines 109-118)

    @Test("detects animation without state change in perform: argument")
    func detectsNoStateChangeInPerformArgument() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Button("Tap") {
                    withAnimation(.easeIn, perform: {
                        print("no mutation here")
                    })
                }
            }
        }
        """

        let visitor = try makeVisitor(for: .animationWithoutStateChange)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .animationWithoutStateChange)
    }

    @Test("allows animation with state change in perform: argument")
    func allowsStateChangeInPerformArgument() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            @State private var isVisible = false

            var body: some View {
                Button("Toggle") {
                    withAnimation(.spring(), perform: {
                        isVisible = true
                    })
                }
            }
        }
        """

        let visitor = try makeVisitor(for: .animationWithoutStateChange)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("detects withAnimation in onAppear with perform: argument")
    func detectsOnAppearWithPerformArgument() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            @State private var isVisible = false

            var body: some View {
                Text("Hello")
                    .onAppear {
                        withAnimation(.easeIn, perform: {
                            isVisible = true
                        })
                    }
            }
        }
        """

        let visitor = try makeVisitor(for: .withAnimationInOnAppear)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .withAnimationInOnAppear)
    }

    // MARK: - Default break case (line 32)
    // The default case is hit when pattern.name is neither .withAnimationInOnAppear
    // nor .animationWithoutStateChange. We can test this by creating a visitor
    // with a different pattern name.

    @Test("withAnimation call with unrelated pattern name does nothing")
    func unrelatedPatternNameDefaultCase() throws {
        // Create a WithAnimationVisitor but with a pattern that has a different name
        let customPattern = SyntaxPattern(
            name: .unknown,
            visitor: WithAnimationVisitor.self,
            severity: .warning,
            category: .animation,
            messageTemplate: "",
            suggestion: "",
            description: ""
        )
        let visitor = WithAnimationVisitor(pattern: customPattern)

        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Button("Tap") {
                    withAnimation {
                        print("hello")
                    }
                }
            }
        }
        """

        runVisitor(visitor, source: source)
        // The default branch should be hit, producing no issues
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - StateMutationChecker: compound operators (line 139)

    @Test("detects state mutation via -= operator")
    func detectsMinusEqualsAsMutation() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            @State private var count = 10

            var body: some View {
                Button("Decrement") {
                    withAnimation {
                        count -= 1
                    }
                }
            }
        }
        """

        let visitor = try makeVisitor(for: .animationWithoutStateChange)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty, "count -= 1 is a state mutation")
    }

    @Test("detects state mutation via *= operator")
    func detectsMultiplyEqualsAsMutation() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            @State private var scale = 1.0

            var body: some View {
                Button("Scale") {
                    withAnimation {
                        scale *= 2.0
                    }
                }
            }
        }
        """

        let visitor = try makeVisitor(for: .animationWithoutStateChange)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty, "scale *= 2.0 is a state mutation")
    }

    // MARK: - Non-mutation function calls should still flag

    @Test("function call without toggle still flags no state change")
    func nonMutationFunctionCallFlags() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Button("Tap") {
                    withAnimation {
                        doSomething()
                    }
                }
            }
        }
        """

        let visitor = try makeVisitor(for: .animationWithoutStateChange)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }
}
