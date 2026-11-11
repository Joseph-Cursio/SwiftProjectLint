import SwiftProjectLintModels
import Testing

/// A walk is reported; a search, a single type assertion, a data index and a test-owned fixture
/// are not. The silent half carries the precision: in the survey behind the rule, nine in ten
/// ViewInspector lookups were already searches, and those must stay quiet.
@Suite
struct PositionalViewLookupVisitorTests {

    func analyze(_ body: String, importing: Bool = true) -> [LintIssue] {
        positionalViewLookupIssues(in: body, importing: importing)
    }

    func analyzeTest(_ statements: String) -> [LintIssue] {
        positionalViewLookupIssues(inTestBody: statements)
    }

    // MARK: - Walks

    @Test("the article's walk is reported once, at its first positional step")
    func articleWalk() {
        let issues = analyzeTest("    _ = try sut.inspect().vStack().hStack(1).button(0)")
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("`.hStack(1)`") == true)
        #expect(issues.first?.severity == .warning)
    }

    @Test("a walk split across locals is followed back to its root")
    func walkThroughLocals() {
        let issues = analyzeTest("""
            let inspected = try sut.inspect()
            let stack = try inspected.vStack()
            let button = try stack.button(0)
            try button.tap()
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.lineNumber == 7)
        #expect(issues.first?.message.contains("`.button(0)`") == true)
    }

    @Test("each lookup through a shared local is its own finding")
    func lookupsThroughSharedLocal() {
        let issues = analyzeTest("""
            let stack = try sut.inspect().vStack()
            _ = try stack.image(0)
            _ = try stack.text(1).string()
        """)
        #expect(issues.map(\.lineNumber) == [6, 7])
    }

    @Test("a second structural step since the anchor walks")
    func secondStructuralStep() {
        let issues = analyzeTest("    _ = try sut.inspect().navigationStack().vStack()")
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("`.vStack()` walks a further level") == true)
    }

    @Test("a multi-line chain is reported on the line of the positional step")
    func multiLineChain() {
        let issues = analyzeTest("""
            _ = try sut.inspect()
                .scrollView()
                .vStack()
        """)
        #expect(issues.first?.lineNumber == 7)
    }

    @Test("parent() climbs, so even one is reported")
    func parentStep() {
        let issues = analyzeTest("""
            let label = try sut.inspect().find(text: "Workspace")
            let row = try label.parent().parent()
            try row.find(ViewType.Button.self).tap()
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("`.parent()`") == true)
        #expect(issues.first?.suggestion?.contains("relation: .parent") == true)
    }

    @Test("parent() is read through optional chaining")
    func parentThroughOptionalChaining() {
        let issues = analyzeTest("""
            let label = try? sut.inspect().find(text: "Clear")
            _ = try label?.parent().find(ViewType.Button.self)
        """)
        #expect(issues.count == 1)
    }

    @Test("an index after find still walks")
    func indexAfterFind() {
        let issues = analyzeTest("    _ = try sut.inspect().find(ViewType.HStack.self).text(1).string()")
        #expect(issues.first?.message.contains("`.text(1)`") == true)
    }

    @Test("a typed index walks")
    func typedIndex() {
        let issues = analyzeTest("    _ = try sut.inspect().tabView().view(SettingsTab.self, 2)")
        #expect(issues.first?.message.contains("`.view(SettingsTab.self, 2)`") == true)
    }

    @Test("a subscript into findAll's matches is positional")
    func findAllSubscript() {
        let issues = analyzeTest("""
            let toggles = try sut.inspect().findAll(ViewType.Toggle.self)
            try toggles[1].tap()
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("`[1]` picks a search match") == true)
    }

    @Test("a subscript into a container's children is positional")
    func childSubscript() {
        let issues = analyzeTest("    _ = try sut.inspect().hStack()[1].text().string()")
        #expect(issues.first?.message.contains("`[1]` picks a child view") == true)
    }

    @Test("a walk inside #expect(throws:) is read through the closure")
    func walkInsideExpectThrows() {
        let issues = analyzeTest("""
            let stack = try sut.inspect().vStack()
            #expect(throws: (any Error).self) { try stack.text(1) }
        """)
        #expect(issues.count == 1)
    }

    @Test("guard let and if let bindings are followed")
    func optionalBindings() {
        let issues = analyzeTest("""
            guard let stack = try? sut.inspect().vStack() else { return }
            _ = try stack.text(0)
            if let row = try? stack.hStack(1) {
                _ = try row.button(0)
            }
        """)
        #expect(issues.map(\.lineNumber) == [6, 7, 8])
    }

    @Test("a relay closure's parameter is an inspected root")
    func relayClosure() {
        let issues = analyze("""
        func testRelay() {
            let exp = sut.inspection.inspect { view in
                _ = try view.vStack().text(0)
            }
            let appeared = sut.on(\\.didAppear) {
                _ = try $0.hStack().button(1)
            }
        }
        """)
        #expect(issues.count == 2)
    }

    @Test("a parameter typed InspectableView is an inspected root")
    func inspectableViewParameter() {
        let issues = analyze("""
        private func firstRow(of list: InspectableView<ViewType.List>) throws -> String {
            try list.hStack(0).text(0).string()
        }
        """)
        #expect(issues.count == 1)
    }

    @Test("a finder helper in extension InspectableView walks from self; x(0) on a found view is a cast")
    func extensionHelper() {
        let issues = analyze("""
        private extension InspectableView {
            func codeChoice(_ index: Int) throws -> InspectableView<ViewType.ClassifiedView> {
                try find(viewWithAccessibilityIdentifier: "codeChoices").vStack(0).forEach(0)[index]
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("`.forEach(0)`") == true)
    }

    @Test("an elements loop over findAll yields inspected views")
    func loopOverMatches() {
        let issues = analyzeTest("""
            for row in try sut.inspect().findAll(RowView.self) {
                _ = try row.hStack().text(1)
            }
        """)
        #expect(issues.count == 1)
    }

    @Test("an import inside #if canImport counts")
    func conditionalImport() {
        let issues = analyze("""
        #if canImport(ViewInspector)
        import ViewInspector
        #endif

        func testThing() throws {
            _ = try CounterView().inspect().vStack().button(0)
        }
        """, importing: false)
        #expect(issues.count == 1)
    }
}
