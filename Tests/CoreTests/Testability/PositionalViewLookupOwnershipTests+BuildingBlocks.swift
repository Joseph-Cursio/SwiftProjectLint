import SwiftProjectLintModels
import Testing

extension PositionalViewLookupOwnershipTests {
    @Test("Self(…) in a declared view's body builds that view again, not an app view")
    func selfInBody() {
        let issues = analyze("""
        private struct Nested: View {
            var depth = 0
            var body: some View { VStack { Text("a"); if depth < 1 { Self(depth: depth + 1) } } }
        }
        private struct Again: View { var body: some View { HStack { Text("b"); Self.init() } } }

        func testNested() throws {
            _ = try Nested().inspect().find(ViewType.VStack.self).text(1)
            _ = try Again().inspect().find(ViewType.HStack.self).text(1)
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test("chart axes, keyframes, layouts, animators, tab sections and toolbar spacers are SwiftUI's")
    func moreBuildingBlocks() {
        let issues = analyze("""
        private struct Axes: View {
            var body: some View {
                VStack { Text("a"); Chart { LinePlot(x: "x", y: "y") }.chartXAxis { AxisMarks() } }
            }
        }
        private struct Frames: View {
            var body: some View {
                VStack { Text("a"); Text("b") }
                    .keyframeAnimator(initialValue: 0.0) { view, _ in view } keyframes: { _ in
                    KeyframeTrack(\\.self) { LinearKeyframe(1.0, duration: 1); SpringKeyframe(0.0) }
                }
            }
        }
        private struct Layouts: View {
            var body: some View { VStack { Text("a"); HStackLayout { Text("b") } } }
        }
        private struct Phases: View {
            var body: some View { VStack { Text("a"); PhaseAnimator([0, 1]) { _ in Text("b") } } }
        }
        private struct Tabs: View {
            var body: some View { TabView { TabSection("s") { Tab("t", systemImage: "x") { Text("a") } } } }
        }
        private struct Spacers: View {
            var body: some View { VStack { Text("a"); Text("b") }.toolbar { ToolbarSpacer() } }
        }

        func testBlocks() throws {
            _ = try Axes().inspect().find(ViewType.VStack.self).text(1)
            _ = try Frames().inspect().find(ViewType.VStack.self).text(1)
            _ = try Layouts().inspect().find(ViewType.VStack.self).text(1)
            _ = try Phases().inspect().find(ViewType.VStack.self).text(1)
            _ = try Tabs().inspect().find(ViewType.TabView.self).text(1)
            _ = try Spacers().inspect().find(ViewType.VStack.self).text(1)
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test("a UIKit wrapper the file declares is a view whose layout it owns")
    func representablesAreViews() {
        let issues = analyze("""
        private struct Wrapped: @preconcurrency UIViewRepresentable & Equatable {
            func makeUIView(context: Context) -> UILabel { UILabel() }
            func updateUIView(_ view: UILabel, context: Context) {}
        }

        func testWrapped() throws {
            let sut = try AnyView(Wrapped()).inspect().anyView().view(Wrapped.self)
            _ = try sut.hStack().text(1)
            _ = try AnyView(AppWrapped()).inspect().anyView().view(AppWrapped.self).hStack().text(1)
        }
        """)
        #expect(issues.map(\.lineNumber) == [11])
    }
}
