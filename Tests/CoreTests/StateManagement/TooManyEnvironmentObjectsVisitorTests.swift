import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct TooManyEnvironmentObjectsVisitorTests {

    private func makeVisitor() -> TooManyEnvironmentObjectsVisitor {
        let pattern = TooManyEnvironmentObjects().pattern
        return TooManyEnvironmentObjectsVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: TooManyEnvironmentObjectsVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    @Test
    func fourEnvironmentObjectsFlags() {
        let source = """
        import SwiftUI

        struct OverloadedView: View {
            @EnvironmentObject var settings: Settings
            @EnvironmentObject var theme: Theme
            @EnvironmentObject var user: UserState
            @EnvironmentObject var navigation: NavigationState

            var body: some View {
                Text("Hello")
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues.first?.ruleName == .tooManyEnvironmentObjects)
    }

    @Test
    func threeEnvironmentObjectsClean() {
        let source = """
        import SwiftUI

        struct ReasonableView: View {
            @EnvironmentObject var settings: Settings
            @EnvironmentObject var theme: Theme
            @EnvironmentObject var user: UserState

            var body: some View {
                Text("Hello")
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func mixedPropertyWrappersOnlyCountsEnvironmentObject() {
        let source = """
        import SwiftUI

        struct MixedView: View {
            @State private var isLoading = false
            @Binding var title: String
            @EnvironmentObject var settings: Settings
            @EnvironmentObject var theme: Theme
            @StateObject private var viewModel = ViewModel()
            @Environment(\\.colorScheme) var colorScheme

            var body: some View {
                Text("Hello")
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func nonViewStructClean() {
        let source = """
        import SwiftUI

        struct NotAView {
            @EnvironmentObject var settings: Settings
            @EnvironmentObject var theme: Theme
            @EnvironmentObject var user: UserState
            @EnvironmentObject var navigation: NavigationState
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func fiveEnvironmentObjectsFlags() {
        let source = """
        import SwiftUI

        struct HeavyView: View {
            @EnvironmentObject var settings: Settings
            @EnvironmentObject var theme: Theme
            @EnvironmentObject var user: UserState
            @EnvironmentObject var navigation: NavigationState
            @EnvironmentObject var analytics: Analytics

            var body: some View {
                Text("Hello")
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func multipleViewsEachEvaluatedSeparately() {
        let source = """
        import SwiftUI

        struct ViewA: View {
            @EnvironmentObject var settings: Settings
            @EnvironmentObject var theme: Theme

            var body: some View { Text("A") }
        }

        struct ViewB: View {
            @EnvironmentObject var alpha: Alpha
            @EnvironmentObject var beta: Beta
            @EnvironmentObject var gamma: Gamma
            @EnvironmentObject var delta: Delta

            var body: some View { Text("B") }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let message = visitor.detectedIssues.first?.message ?? ""
        #expect(message.contains("ViewB"))
    }
}
