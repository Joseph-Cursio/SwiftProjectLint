import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct TaskInOnAppearVisitorTests {

    private func makeVisitor() -> TaskInOnAppearVisitor {
        let pattern = TaskInOnAppearPatternRegistrar().pattern
        return TaskInOnAppearVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: TaskInOnAppearVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsTaskInsideOnAppear() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .onAppear {
                        Task {
                            await loadData()
                        }
                    }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .taskInOnAppear)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("Task created inside .onAppear"))
    }

    @Test
    func testDetectsTaskDetachedInsideOnAppear() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .onAppear {
                        Task.detached {
                            await doWork()
                        }
                    }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .taskInOnAppear)
        #expect(issue.severity == .warning)
    }

    @Test
    func testDetectsOnAppearWithPerformArgument() throws {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .onAppear(perform: {
                        Task {
                            await loadData()
                        }
                    })
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForTaskModifier() {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .task {
                        await loadData()
                    }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForTaskInButtonAction() {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Button("Tap") {
                    Task {
                        await performAction()
                    }
                }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForOnDisappear() {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .onDisappear {
                        cleanup()
                    }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForTaskInSeparateFunction() {
        let source = """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .onAppear {
                        startLoading()
                    }
            }

            func startLoading() {
                Task {
                    await loadData()
                }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
