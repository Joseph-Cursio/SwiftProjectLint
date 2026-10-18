@testable import Core
import Testing

/// Whose layout a chain walks: a test-declared view reached through a capture or a factory, and a
/// test-declared host that wraps an app view.
@Suite
struct PositionalViewLookupOwnershipTests {

    private func analyze(_ body: String) -> [LintIssue] {
        positionalViewLookupIssues(in: body)
    }

    @Test("a self-named capture reads the outer binding")
    func selfNamedCapture() {
        let issues = analyze("""
        private struct ProbeView: View { var body: some View { VStack { Text("a"); Text("b") } } }

        func testCaptures() throws {
            let probe = ProbeView()
            let stack = try sut.inspect().find(ViewType.VStack.self)
            DispatchQueue.main.async { [probe = probe] in _ = try? probe.inspect().vStack().text(1) }
            DispatchQueue.main.async { [stack = stack] in _ = try? stack.hStack(1) }
        }
        """)
        #expect(issues.map(\.lineNumber) == [9])
    }

    @Test("a factory is the one its call can reach: self., Self., the type's name, the enclosing suite")
    func factoriesByOwner() {
        let issues = analyze("""
        private struct GeometryProbe: View {
            var body: some View { GeometryReader { _ in HStack { Text("a"); Text("b") } } }
        }

        @Suite struct GeometryProbeTests {
            func makeSUT() -> GeometryProbe { GeometryProbe() }
            static func makeShared() -> GeometryProbe { GeometryProbe() }

            @Test func probe() throws {
                _ = try self.makeSUT().inspect().geometryReader().hStack().text(1)
                _ = try Self.makeShared().inspect().geometryReader().hStack().text(1)
                _ = try GeometryProbeTests.makeShared().inspect().geometryReader().hStack().text(1)
            }
        }

        @Suite struct SettingsScreenTests {
            func makeSUT() -> SettingsScreen { SettingsScreen() }

            @Test func screen() throws {
                _ = try makeSUT().inspect().form().section(1)
            }
        }
        """)
        #expect(issues.map(\.lineNumber) == [22])
    }

    @Test("a search or a climb inside a host that wraps an app view walks the app's layout")
    func hostWrappingAppView() {
        let issues = analyze("""
        private struct HostView: View {
            @State var values: [String: Int] = [:]
            var body: some View { RuleParameterEditor(values: $values).onAppear { Store().load() } }
        }
        private struct LeafProbe: View { var body: some View { VStack { Text("a"); Text("b") } } }

        func testHost() throws {
            let host = HostView()
            _ = try host.inspect().find(ViewType.Form.self).section(1)
            _ = try host.inspect().find(text: "line_length").parent().parent()
            _ = try host.inspect().findAll(ViewType.Toggle.self)[1]
            _ = try host.inspect().find(ViewType.Text.self, skipFound: 1)
            _ = try LeafProbe().inspect().find(ViewType.VStack.self).text(1)
            _ = try LeafProbe().inspect().findAll(ViewType.Text.self)[1]
        }
        """)
        #expect(issues.map(\.lineNumber) == [11, 12, 13, 14])
    }

    @Test("an action closure in a probe's body builds no view")
    func actionClosuresBuildNothing() {
        let issues = analyze("""
        private struct Probe: View {
            var body: some View {
                VStack { Text("a"); Text("b") }
                    .onAppear { Store().load() }
                    .task { await Loader().run() }
            }
        }

        func testProbe() throws {
            _ = try Probe().inspect().find(ViewType.VStack.self).text(1)
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test("a Button's action, a task, a chart's marks and a declared shape build no app view")
    func probeBodiesThatBuildNoAppView() {
        let issues = analyze("""
        private struct Triangle: Shape { func path(in rect: CGRect) -> Path { Path() } }
        private struct Probe: View {
            @State var loaded = false
            var body: some View {
                VStack {
                    Text("a"); Text("b")
                    Button("Load") { Task { loaded = true } }
                    Button { Task { loaded = false } } label: { Text("Reset") }
                    Chart { BarMark(x: .value("x", 1), y: .value("y", 2)) }
                    Triangle()
                }
            }
        }

        func testProbe() throws {
            _ = try Probe().inspect().find(ViewType.VStack.self).text(1)
            _ = try Probe().inspect().find(text: "a").parent().parent()
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test("same-named views in one file are a host only when each builds an app view")
    func sameNamedNestedViews() {
        let issues = analyze("""
        final class EditorTests: XCTestCase {
            private struct HostView: View { var body: some View { RuleEditor() } }
        }

        final class LayoutProbeTests: XCTestCase {
            private struct HostView: View { var body: some View { VStack { Text("a"); Text("b") } } }
            func testProbe() throws {
                _ = try HostView().inspect().findAll(ViewType.Text.self)[1]
            }
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test("a computed some View member, AnyView(…) and overlay(…) build the views they hold")
    func factoredBodies() {
        let issues = analyze("""
        private struct ComputedHost: View {
            var body: some View { editor.padding() }
            private var editor: some View { RuleEditor() }
        }
        private struct WrappedHost: View { var body: some View { AnyView(RuleEditor()) } }
        private struct OverlayHost: View { var body: some View { Text("x").overlay(RuleBadge()) } }

        func testHosts() throws {
            _ = try ComputedHost().inspect().find(ViewType.Form.self).section(1)
            _ = try WrappedHost().inspect().find(ViewType.Form.self).section(1)
            _ = try OverlayHost().inspect().find(ViewType.HStack.self).text(1)
        }
        """)
        #expect(issues.map(\.lineNumber) == [11, 12, 13])
    }

    @Test("a factory returning Self, a static property and an optional relay keep a probe's ownership")
    func moreOwnedSubjects() {
        let issues = analyze("""
        private struct Probe: View {
            static func make() -> Self { Self() }
            static let shared = Probe()
            static var preview: Probe { Probe() }
            var inspection: Inspection<Self>? = Inspection()
            var body: some View { VStack { Text("a"); HStack { Text("b"); Text("c") } } }
        }

        func testProbe() throws {
            _ = try Probe.make().inspect().vStack().hStack(1)
            _ = try Probe.shared.inspect().vStack().hStack(1)
            _ = try Probe.preview.inspect().vStack().hStack(1)
            let probe = Probe()
            probe.inspection?.inspect { view in _ = try view.vStack().hStack(1) }
            probe.inspection!.inspect { view in _ = try view.vStack().hStack(1) }
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test("a test-declared view reached through a loop variable or an iterating closure stays owned")
    func ownedThroughIteration() {
        let issues = analyze("""
        private struct Probe: View { var body: some View { VStack { Text("a"); Text("b") } } }

        func testProbes(_ variadic: Probe..., typed: [Probe]) throws {
            for probe in [Probe(), Probe()] { _ = try probe.inspect().vStack().text(1) }
            [Probe()].forEach { probe in _ = try? probe.inspect().vStack().text(1) }
            let probes = [Probe()]
            for probe in probes { _ = try probe.inspect().vStack().text(1) }
            for probe in variadic { _ = try probe.inspect().vStack().text(1) }
            _ = try typed.map { try $0.inspect().vStack().text(1) }
            for screen in [AppScreen()] { _ = try screen.inspect().vStack().text(1) }
            for view in [Probe(), AppScreen()] { _ = try view.inspect().vStack().text(1) }
        }
        """)
        #expect(issues.map(\.lineNumber) == [12, 13])
    }

    @Test("inspect() called inside an extension of a test-declared view walks that view's layout")
    func unqualifiedInspectInOwnedExtension() {
        let issues = analyze("""
        private struct Probe: View { var body: some View { VStack { Text("a"); Text("b") } } }
        extension Probe {
            func check() throws { _ = try inspect().vStack().text(1) }
        }
        extension AppScreen {
            func check() throws { _ = try inspect().vStack().text(1) }
        }
        """)
        #expect(issues.map(\.lineNumber) == [8])
    }

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
