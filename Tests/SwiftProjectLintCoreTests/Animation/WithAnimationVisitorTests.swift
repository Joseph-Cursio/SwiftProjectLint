import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct WithAnimationVisitorTests {

    private func makeVisitor(for rule: RuleIdentifier) -> WithAnimationVisitor {
        let patterns = WithAnimationPatternRegistrar().patterns
        // swiftlint:disable:next force_unwrapping
        let pattern = patterns.first { $0.name == rule }!
        return WithAnimationVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: WithAnimationVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - withAnimation in onAppear

    @Test
    func detectsWithAnimationInOnAppear() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            @State private var isVisible = false

            var body: some View {
                Text("Hello")
                    .onAppear {
                        withAnimation {
                            isVisible = true
                        }
                    }
            }
        }
        """

        let visitor = makeVisitor(for: .withAnimationInOnAppear)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .withAnimationInOnAppear)
        #expect(issue.severity == .warning)
    }

    @Test
    func allowsWithAnimationOutsideOnAppear() {
        let source = """
        import SwiftUI

        struct MyView: View {
            @State private var isVisible = false

            var body: some View {
                Button("Toggle") {
                    withAnimation {
                        isVisible = true
                    }
                }
            }
        }
        """

        let visitor = makeVisitor(for: .withAnimationInOnAppear)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func detectsNestedWithAnimationInOnAppear() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            @State private var isVisible = false

            var body: some View {
                Text("Hello")
                    .onAppear {
                        someFunction {
                            withAnimation {
                                isVisible = true
                            }
                        }
                    }
            }
        }
        """

        let visitor = makeVisitor(for: .withAnimationInOnAppear)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .withAnimationInOnAppear)
    }

    // MARK: - Animation Without State Change

    @Test
    func detectsAnimationWithoutStateChange() throws {
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

        let visitor = makeVisitor(for: .animationWithoutStateChange)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .animationWithoutStateChange)
        #expect(issue.severity == .info)
    }

    @Test
    func detectsEmptyWithAnimationClosure() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Button("Tap") {
                    withAnimation { }
                }
            }
        }
        """

        let visitor = makeVisitor(for: .animationWithoutStateChange)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .animationWithoutStateChange)
    }

    @Test
    func allowsAnimationWithAssignment() {
        let source = """
        import SwiftUI

        struct MyView: View {
            @State private var isVisible = false

            var body: some View {
                Button("Toggle") {
                    withAnimation {
                        isVisible = true
                    }
                }
            }
        }
        """

        let visitor = makeVisitor(for: .animationWithoutStateChange)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func allowsAnimationWithToggle() {
        let source = """
        import SwiftUI

        struct MyView: View {
            @State private var isVisible = false

            var body: some View {
                Button("Toggle") {
                    withAnimation {
                        isVisible.toggle()
                    }
                }
            }
        }
        """

        let visitor = makeVisitor(for: .animationWithoutStateChange)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func allowsAnimationWithCompoundAssignment() {
        let source = """
        import SwiftUI

        struct MyView: View {
            @State private var count = 0

            var body: some View {
                Button("Increment") {
                    withAnimation {
                        count += 1
                    }
                }
            }
        }
        """

        let visitor = makeVisitor(for: .animationWithoutStateChange)
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func bothRulesDetectedInSameFile() {
        let source = """
        import SwiftUI

        struct MyView: View {
            @State private var isVisible = false

            var body: some View {
                VStack {
                    Text("Hello")
                        .onAppear {
                            withAnimation {
                                isVisible = true
                            }
                        }

                    Button("Tap") {
                        withAnimation {
                            print("no mutation")
                        }
                    }
                }
            }
        }
        """

        // Test withAnimationInOnAppear
        let onAppearVisitor = makeVisitor(for: .withAnimationInOnAppear)
        runVisitor(onAppearVisitor, source: source)
        #expect(onAppearVisitor.detectedIssues.count == 1)
        #expect(onAppearVisitor.detectedIssues.first?.ruleName == .withAnimationInOnAppear)

        // Test animationWithoutStateChange
        let noStateVisitor = makeVisitor(for: .animationWithoutStateChange)
        runVisitor(noStateVisitor, source: source)
        #expect(noStateVisitor.detectedIssues.count == 1)
        #expect(noStateVisitor.detectedIssues.first?.ruleName == .animationWithoutStateChange)
    }
}
