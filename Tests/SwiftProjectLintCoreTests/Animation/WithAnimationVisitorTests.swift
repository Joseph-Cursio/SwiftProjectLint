import XCTest
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

final class WithAnimationVisitorTests: XCTestCase {

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

    func testDetectsWithAnimationInOnAppear() throws {
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

        XCTAssertEqual(visitor.detectedIssues.count, 1)

        let issue = try XCTUnwrap(visitor.detectedIssues.first)
        XCTAssertEqual(issue.ruleName, .withAnimationInOnAppear)
        XCTAssertEqual(issue.severity, .warning)
    }

    func testAllowsWithAnimationOutsideOnAppear() {
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

        XCTAssertTrue(visitor.detectedIssues.isEmpty)
    }

    func testDetectsNestedWithAnimationInOnAppear() throws {
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

        XCTAssertEqual(visitor.detectedIssues.count, 1)

        let issue = try XCTUnwrap(visitor.detectedIssues.first)
        XCTAssertEqual(issue.ruleName, .withAnimationInOnAppear)
    }

    // MARK: - Animation Without State Change

    func testDetectsAnimationWithoutStateChange() throws {
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

        XCTAssertEqual(visitor.detectedIssues.count, 1)

        let issue = try XCTUnwrap(visitor.detectedIssues.first)
        XCTAssertEqual(issue.ruleName, .animationWithoutStateChange)
        XCTAssertEqual(issue.severity, .info)
    }

    func testDetectsEmptyWithAnimationClosure() throws {
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

        XCTAssertEqual(visitor.detectedIssues.count, 1)

        let issue = try XCTUnwrap(visitor.detectedIssues.first)
        XCTAssertEqual(issue.ruleName, .animationWithoutStateChange)
    }

    func testAllowsAnimationWithAssignment() {
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

        XCTAssertTrue(visitor.detectedIssues.isEmpty)
    }

    func testAllowsAnimationWithToggle() {
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

        XCTAssertTrue(visitor.detectedIssues.isEmpty)
    }

    func testAllowsAnimationWithCompoundAssignment() {
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

        XCTAssertTrue(visitor.detectedIssues.isEmpty)
    }

    func testBothRulesDetectedInSameFile() {
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
        XCTAssertEqual(onAppearVisitor.detectedIssues.count, 1)
        XCTAssertEqual(onAppearVisitor.detectedIssues.first?.ruleName, .withAnimationInOnAppear)

        // Test animationWithoutStateChange
        let noStateVisitor = makeVisitor(for: .animationWithoutStateChange)
        runVisitor(noStateVisitor, source: source)
        XCTAssertEqual(noStateVisitor.detectedIssues.count, 1)
        XCTAssertEqual(noStateVisitor.detectedIssues.first?.ruleName, .animationWithoutStateChange)
    }
}
