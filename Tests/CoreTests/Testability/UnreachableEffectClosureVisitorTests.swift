@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Drives the visitor over `source` and returns just this rule's findings.
///
/// At file scope for the same reason `PureClosureCandidateVisitorTests` does it: the suite's only
/// helper, kept out of the type so `type_body_length` has room as tests accumulate.
private func analyze(_ source: String, filePath: String = "ContentView.swift") -> [LintIssue] {
    let visitor = UnreachableEffectClosureVisitor(patternCategory: .testability)
    let syntax = Parser.parse(source: source)
    visitor.setSourceLocationConverter(
        SourceLocationConverter(fileName: filePath, tree: syntax)
    )
    visitor.setFilePath(filePath)
    visitor.walk(syntax)
    return visitor.detectedIssues.filter { $0.ruleName == .unreachableEffectClosure }
}

/// The effect nobody can assert on.
///
/// `pureClosureCandidate` argues from **reachability** — an inline closure has no name to call and
/// no seam to reach it through — and then narrows to pure closures, refuting anything that writes to
/// what it captured. Right for a property-test seed, wrong as a conclusion about extraction: the
/// unreachability claim never depended on purity. This rule covers what falls through.
///
/// The measured case is SwiftUMLStudio's `NativeDiagramView`, where hover and key-press handlers
/// wrote to a captured `viewport` and sat at 0% coverage — `ImageRenderer` never fires gestures, and
/// ViewInspector cannot traverse a body that is a `GeometryReader`.
@Suite("Effectful callback closures are unreachable")
struct UnreachableEffectClosureVisitorTests {

    // MARK: - The motivating case

    @Test("a key-press handler writing captured state is reported")
    func keyPressWritingCaptureIsReported() {
        let issues = analyze("""
        struct DiagramView: View {
            var body: some View {
                canvas.onKeyPress(.escape) {
                    viewport.selectedNodeId = nil
                    return .handled
                }
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("onKeyPress") == true)
        #expect(issues.first?.severity == .info)
    }

    @Test("a hover handler writing captured state is reported")
    func hoverWritingCaptureIsReported() {
        let issues = analyze("""
        struct DiagramView: View {
            var body: some View {
                canvas.onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        viewport.hoveredNodeId = hitNode(at: location)?.id
                    case .ended:
                        viewport.hoveredNodeId = nil
                    }
                }
            }
        }
        """)
        #expect(issues.count == 1)
    }

    @Test("the finding names the enclosing declaration, since a closure has no name of its own")
    func findingNamesTheEnclosingDeclaration() {
        let issues = analyze("""
        struct DiagramView: View {
            var body: some View {
                canvas.onTapGesture {
                    selectedId = nil
                    lastTapCount += 1
                }
            }
        }
        """)
        #expect(issues.first?.symbol == "body")
    }

    @Test("the suggestion is not the pure sibling's — captures do not become parameters here")
    func suggestionDiffersFromThePureSibling() {
        let issues = analyze("""
        view.onTapGesture {
            selectedId = nil
            count += 1
        }
        """)
        let suggestion = issues.first?.suggestion ?? ""
        #expect(suggestion.contains("named method"))
        #expect(suggestion.contains("becomes a parameter") == false)
    }

    // MARK: - Convergence (condition 3)

    @Test("the fixed form is not reported — otherwise the rule fires forever")
    func singleCallBodyIsNotReported() {
        // `.onKeyPress(.escape) { clearSelection() }` is what acting on this rule produces. Report
        // it and the advice can never be satisfied, which is how a rule gets switched off.
        #expect(analyze("view.onKeyPress(.escape) { clearSelection() }").isEmpty)
    }

    @Test("a returned single call is the fixed form too")
    func returnedSingleCallIsNotReported() {
        #expect(analyze("view.onKeyPress(.escape) { return clearSelection() }").isEmpty)
    }

    @Test("an empty body has nothing to extract")
    func emptyBodyIsNotReported() {
        #expect(analyze("view.onTapGesture { }").isEmpty)
    }

    @Test("a single assignment IS reported — it has no name either")
    func singleAssignmentIsReported() {
        // The deliberate asymmetry with `{ clear() }`: one has a seam, the other does not. Naming
        // it is exactly the fix this rule asks for.
        #expect(analyze("view.onTapGesture { selectedId = nil }").count == 1)
    }

    // MARK: - Refutations

    @Test("a read-only closure is not this rule's business")
    func readOnlyClosureIsNotReported() {
        #expect(analyze("""
        view.onTapGesture {
            logger.debug("tapped \\(selectedId)")
            report(selectedId)
        }
        """).isEmpty)
    }

    @Test("writes to the closure's own locals never escape")
    func localOnlyWritesAreNotReported() {
        #expect(analyze("""
        view.onTapGesture {
            var count = 0
            count += 1
            print(count)
        }
        """).isEmpty)
    }

    @Test("a nested reduce(into:) accumulator is a local, not a capture")
    func nestedAccumulatorIsNotReported() {
        // The case the SEI pin this rule landed on exists to get right: `total` is the inner
        // closure's own parameter. Before that fix this reported, contradicting the rule's own
        // refutation list.
        #expect(analyze("""
        view.onTapGesture {
            let sum = values.reduce(into: 0) { total, value in total += value }
            print(sum)
        }
        """).isEmpty)
    }

    @Test("test files are skipped")
    func testFilesAreSkipped() {
        #expect(analyze("""
        view.onTapGesture {
            selectedId = nil
            count += 1
        }
        """, filePath: "DiagramViewTests.swift").isEmpty)
    }

    // MARK: - The allowlist (condition 1)

    @Test("onAppear and onDisappear are deliberately absent")
    func lifecycleModifiersAreNotReported() {
        // `impureCallInViewBody` tells a reader to move effects INTO `onAppear`. Reporting it here
        // would hand them straight back, and two rules passing someone back and forth is how a
        // category gets disabled.
        for modifier in ["onAppear", "onDisappear"] {
            #expect(analyze("""
            view.\(modifier) {
                isLoaded = true
                count += 1
            }
            """).isEmpty)
        }
    }

    @Test("an unlisted modifier is a missed finding, not an inferred one")
    func unlistedModifierIsNotReported() {
        // Prefer under-reporting. Inferring "any trailing closure on a member access" would sweep
        // in every custom view builder.
        #expect(analyze("""
        view.onReceive(timer) {
            tick += 1
            lastTick = Date()
        }
        """).isEmpty)
    }

    @Test("a ViewBuilder closure is not a callback")
    func viewBuilderClosureIsNotReported() {
        #expect(analyze("""
        ForEach(rows) { row in
            rendered = row
            total += 1
        }
        """).isEmpty)
    }

    @Test("gesture callbacks count")
    func gestureCallbacksAreReported() {
        #expect(analyze("""
        DragGesture().onChanged { value in
            offset = value.translation
            isDragging = true
        }
        """).count == 1)
    }

    // MARK: - Button, the second surface

    @Test("a multi-statement Button action is reported")
    func multiStatementButtonActionIsReported() {
        // The widening past the original proposal. `buttonClosureWrapping` owns only the
        // single-call form, so without this arm nothing reports the common case.
        let issues = analyze("""
        Button("Save") {
            count += 1
            save()
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Button") == true)
    }

    @Test("a single-call Button action belongs to buttonClosureWrapping")
    func singleCallButtonActionIsNotReported() {
        // The two rules cannot collide: that one fires only on this shape, which condition 3
        // already excludes here.
        #expect(analyze("""
        Button("Save") { save() }
        """).isEmpty)
    }

    @Test("the label closure is not mistaken for the action")
    func buttonLabelIsNotMistakenForTheAction() {
        // `Button(action:) { label }` puts a @ViewBuilder in the trailing position. Reading the
        // trailing closure blindly would report the label, which is not a callback at all.
        let issues = analyze("""
        Button(action: { save() }) {
            Text(title)
            Image(systemName: icon)
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test("the action is found through an explicit action: label")
    func explicitActionArgumentIsReported() {
        let issues = analyze("""
        Button(action: {
            count += 1
            save()
        }) {
            Text(title)
        }
        """)
        #expect(issues.count == 1)
    }

    @Test("the trailing-action form with a label: closure is reported")
    func trailingActionWithLabelClosureIsReported() {
        let issues = analyze("""
        Button {
            count += 1
            save()
        } label: {
            Text(title)
        }
        """)
        #expect(issues.count == 1)
    }
}
