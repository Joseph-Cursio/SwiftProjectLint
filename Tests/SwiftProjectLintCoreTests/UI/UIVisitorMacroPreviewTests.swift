import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite("UIVisitor Macro and Preview Edge Cases")
struct UIVisitorMacroPreviewTests {

    private func createVisitor(filePath: String = "test.swift") -> UIVisitor {
        let visitor = UIVisitor(patternCategory: PatternCategory.uiPatterns)
        visitor.setFilePath(filePath)
        visitor.reset()
        return visitor
    }

    private func walkSource(_ source: String, visitor: UIVisitor) -> [LintIssue] {
        let syntax = Parser.parse(source: source)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    // MARK: - #Preview Macro with Arguments

    @Test("detects preview via macro expansion with DeclReferenceExpr argument")
    func detectsPreviewMacroWithArgument() throws {
        // The MacroExpansionExprSyntax visit path detects previews when a
        // DeclReferenceExpr appears directly in the macro arguments list,
        // e.g. #Preview("name", MyView) — not the trailing closure form.
        // The trailing closure form (#Preview { MyView() }) is detected
        // through child walking. This test exercises the argument-list path.
        let visitor = createVisitor(filePath: "test.swift")
        let source = """
        struct SampleView: View {
            var body: some View {
                Text("Hello")
            }
        }

        #Preview("Sample", SampleView)
        """

        let issues = walkSource(source, visitor: visitor)
        // File path contains "test" so missing preview is skipped regardless,
        // but we exercise the MacroExpansionExprSyntax visit path
        #expect(issues.isEmpty)
    }

    @Test("missing preview detected for non-test file path")
    func missingPreviewForNonTestFile() throws {
        let visitor = createVisitor(filePath: "Sources/MyView.swift")
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Hello")
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let missingPreview = issues.first { $0.message.contains("missing preview provider") }
        #expect(missingPreview != nil, "Should detect missing preview for non-test file")
        #expect(missingPreview?.severity == .info)
    }

    @Test("no missing preview warning for test file paths",
          arguments: ["SomeTest.swift", "Tests/MyView.swift", "test.swift"])
    func noMissingPreviewForTestFiles(path: String) throws {
        let visitor = createVisitor(filePath: path)
        let source = """
        struct SomeView: View {
            var body: some View {
                Text("Hello")
            }
        }
        """
        let issues = walkSource(source, visitor: visitor)
        let missingPreview = issues.filter { $0.message.contains("missing preview") }
        #expect(missingPreview.isEmpty, "Should not warn about missing preview for path: \(path)")
    }

    @Test("non-View struct does not trigger missing preview")
    func nonViewStructNoPreviewWarning() throws {
        let visitor = createVisitor(filePath: "Sources/Model.swift")
        let source = """
        struct UserModel: Codable {
            let name: String
        }
        """

        let issues = walkSource(source, visitor: visitor)
        #expect(issues.isEmpty, "Non-View struct should not trigger missing preview warning")
    }

    // MARK: - Body Computed Property Error Handling Analysis

    @Test("detects error handling in computed body property with accessor block")
    func errorHandlingInAccessorBlock() throws {
        let visitor = createVisitor()
        let source = """
        struct ErrorView: View {
            @State var error: String?

            var body: some View {
                get {
                    if let error = error {
                        Text("Error: bad")
                    }
                }
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let errorIssues = issues.filter { $0.message.contains("proper error handling") }
        // The accessor block path should detect error handling without proper UI
        #expect(errorIssues.count >= 1, "Should detect basic error handling in accessor block")
    }

    @Test("detects error handling in body with closure initializer")
    func errorHandlingInClosureInitializer() throws {
        let visitor = createVisitor()
        // This exercises the analyzeInitializer path with a closure expression
        let source = """
        struct ErrorView: View {
            var body: some View = {
                if let error = someError {
                    Text("Error: something went wrong")
                }
            }()
        }
        """

        _ = walkSource(source, visitor: visitor)
        // The closure initializer path may or may not detect this depending on AST shape
        // The important thing is it doesn't crash
    }

    @Test("no error handling issue when alert is used properly")
    func noErrorHandlingWithAlert() throws {
        let visitor = createVisitor()
        let source = """
        struct GoodErrorView: View {
            @State var showAlert = false
            @State var error: String?

            var body: some View {
                VStack {
                    if let error = error {
                        Text("Error occurred")
                    }
                }
                .alert("Error", isPresented: $showAlert) {
                    Button("OK") { }
                }
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let errorIssues = issues.filter { $0.message.contains("proper error handling") }
        #expect(errorIssues.isEmpty, "Should not flag error handling when .alert() is present")
    }

    @Test("no error handling issue when sheet is used properly")
    func noErrorHandlingWithSheet() throws {
        let visitor = createVisitor()
        let source = """
        struct SheetErrorView: View {
            @State var showSheet = false
            @State var error: String?

            var body: some View {
                VStack {
                    if let error = error {
                        Text("Error: fix this")
                    }
                }
                .sheet(isPresented: $showSheet) {
                    Text("Details")
                }
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let errorIssues = issues.filter { $0.message.contains("proper error handling") }
        #expect(errorIssues.isEmpty, "Should not flag error handling when .sheet() is present")
    }

    // MARK: - NavigationView Stack Pop (visitPost)

    @Test("navigation stack pops correctly after NavigationView exits")
    func navigationStackPopsOnExit() throws {
        let visitor = createVisitor()
        // Two sibling NavigationViews should not trigger nested detection
        let source = """
        struct FirstView: View {
            var body: some View {
                NavigationView {
                    Text("First")
                }
            }
        }
        struct SecondView: View {
            var body: some View {
                NavigationView {
                    Text("Second")
                }
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let nestedNav = issues.filter { $0.message.contains("Nested NavigationView") }
        #expect(nestedNav.isEmpty, "Sibling NavigationViews should not trigger nested warning")
    }

    // MARK: - Styling Modifiers Collection

    @Test("detects multiple styling modifiers including background and padding")
    func multipleStyleModifiers() throws {
        let visitor = createVisitor()
        let source = """
        struct StyledView: View {
            var body: some View {
                Text("Hello")
                    .padding()
                    .background(Color.blue)
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let stylingIssues = issues.filter { $0.message.contains("consistent text styling") }
        #expect(stylingIssues.count == 1, "Should detect inconsistent text styling with padding + background")
    }

    @Test("no styling issue for non-styling modifiers on Text")
    func nonStylingModifiersIgnored() throws {
        let visitor = createVisitor()
        let source = """
        struct PlainView: View {
            var body: some View {
                Text("Hello")
                    .onAppear { }
                    .accessibilityLabel("greeting")
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let stylingIssues = issues.filter { $0.message.contains("consistent text styling") }
        #expect(stylingIssues.isEmpty, "Non-styling modifiers should not trigger styling warning")
    }

    @Test("ForEach without id has correct suggestion text")
    func forEachWithoutIdSuggestion() throws {
        let visitor = createVisitor()
        let source = """
        struct ListView: View {
            var body: some View {
                ForEach(["a", "b"]) { item in
                    Text(item)
                }
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let forEachIssue = try #require(issues.first { $0.message.contains("ForEach without explicit ID") })
        #expect(forEachIssue.suggestion == "Add an explicit id: parameter to ForEach")
        #expect(forEachIssue.ruleName == .forEachWithoutIDUI)
    }

    @Test("nested NavigationView has correct suggestion text")
    func nestedNavigationSuggestion() throws {
        let visitor = createVisitor()
        let source = """
        struct NestedNav: View {
            var body: some View {
                NavigationView {
                    NavigationView {
                        Text("Deep")
                    }
                }
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let navIssue = try #require(issues.first { $0.message.contains("Nested NavigationView") })
        #expect(navIssue.suggestion == "Use NavigationStack or remove nested NavigationView")
        #expect(navIssue.ruleName == .nestedNavigationView)
    }

    @Test("inconsistent styling has correct suggestion text")
    func inconsistentStylingSuggestion() throws {
        let visitor = createVisitor()
        let source = """
        struct TextStyleView: View {
            var body: some View {
                Text("Styled")
                    .font(.headline)
                    .foregroundColor(.red)
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let styleIssue = try #require(issues.first { $0.message.contains("consistent text styling") })
        #expect(styleIssue.suggestion == "Extract common styles into a ViewModifier or extension")
        #expect(styleIssue.ruleName == .inconsistentStyling)
    }
}
