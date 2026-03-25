import Testing
@testable import Core
import SwiftSyntax
import SwiftParser

@Suite
struct TaskInOnAppearVisitorTests {

    private func makeVisitor() -> TaskInOnAppearVisitor {
        let pattern = TaskInOnAppear().pattern
        return TaskInOnAppearVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: TaskInOnAppearVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func detectsTaskInsideOnAppear() throws {
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

    @Test("Detects Task variant in onAppear", arguments: [
        // Task.detached inside onAppear
        """
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
        """,
        // onAppear with perform: argument
        """
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
    ])
    func detectsVariant(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative Cases

    @Test("No issue for non-onAppear Task usage", arguments: [
        // .task modifier
        """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .task {
                        await loadData()
                    }
            }
        }
        """,
        // Task in button action
        """
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
        """,
        // onDisappear (not onAppear)
        """
        import SwiftUI

        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .onDisappear {
                        cleanup()
                    }
            }
        }
        """,
        // Task in separate function
        """
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
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
