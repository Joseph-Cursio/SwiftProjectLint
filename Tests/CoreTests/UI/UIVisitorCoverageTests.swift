import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

/// Coverage tests for uncovered paths in UIVisitor.swift:
/// - #Preview attribute on struct (lines 41-43)
/// - FunctionDeclSyntax body analysis (lines 61-66)
/// - Closure initializer body analysis (lines 195-196)
/// - analyzeBodyForBasicErrorHandling via func body (lines 257-277)
/// - hasComplexDependencies ViewModel check (line 247)
@Suite("UIVisitor Coverage Tests")
struct UIVisitorCoverageTests {

    private func createVisitor(filePath: String = "Sources/MyView.swift") -> UIVisitor {
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

    // MARK: - FunctionDeclSyntax body analysis (lines 61-66)

    @Test("detects error handling in func body declaration")
    func errorHandlingInFuncBody() throws {
        let visitor = createVisitor()
        let source = """
        struct ErrorView: View {
            @State var error: String?

            func body() -> some View {
                if let error = error {
                    Text("Error: bad stuff")
                }
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let errorIssues = issues.filter { $0.message.contains("proper error handling") }
        // The func body path should detect basic error handling pattern
        #expect(errorIssues.count >= 1)
    }

    @Test("func body with proper .alert does not flag error handling")
    func funcBodyWithAlertNoIssue() throws {
        let visitor = createVisitor()
        let source = """
        struct GoodView: View {
            func body() -> some View {
                VStack {
                    if let error = someError {
                        Text("Error: occurred")
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
        #expect(errorIssues.isEmpty)
    }

    // MARK: - Closure initializer body analysis (lines 194-196)

    @Test("analyzes body closure initializer for error handling")
    func closureInitializerErrorHandling() throws {
        let visitor = createVisitor(filePath: "test.swift")
        let source = """
        struct ClosureView: View {
            var body: some View = {
                if let error = appError {
                    Text("Error: something broke")
                }
                return Text("OK")
            }()
        }
        """

        let issues = walkSource(source, visitor: visitor)
        // This exercises the analyzeInitializer path (line 194-196)
        let errorIssues = issues.filter { $0.ruleName == .basicErrorHandling }
        #expect(errorIssues.count >= 1)
    }

    // MARK: - hasComplexDependencies: ViewModel-typed property (line 247)

    @Test("view with ViewModel-typed property is not flagged for missing preview")
    func viewModelPropertySuppressesMissingPreview() throws {
        let visitor = createVisitor(filePath: "Sources/SettingsView.swift")
        let source = """
        struct SettingsView: View {
            var settingsViewModel: SettingsViewModel

            var body: some View {
                Text("Settings")
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let previewIssues = issues.filter { $0.ruleName == .missingPreview }
        #expect(previewIssues.isEmpty, "View with ViewModel dependency should not be flagged for missing preview")
    }

    @Test("view with @Bindable property is not flagged for missing preview")
    func bindablePropertySuppressesMissingPreview() throws {
        let visitor = createVisitor(filePath: "Sources/DetailView.swift")
        let source = """
        struct DetailView: View {
            @Bindable var model: ItemModel

            var body: some View {
                Text("Detail")
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let previewIssues = issues.filter { $0.ruleName == .missingPreview }
        #expect(previewIssues.isEmpty, "View with @Bindable dependency should not be flagged for missing preview")
    }

    @Test("view with @Environment property is not flagged for missing preview")
    func environmentPropertySuppressesMissingPreview() throws {
        let visitor = createVisitor(filePath: "Sources/ThemeView.swift")
        let source = """
        struct ThemeView: View {
            @Environment(\\.colorScheme) var colorScheme

            var body: some View {
                Text("Theme")
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let previewIssues = issues.filter { $0.ruleName == .missingPreview }
        #expect(previewIssues.isEmpty, "View with @Environment dependency should not be flagged for missing preview")
    }

    @Test("view with @EnvironmentObject property is not flagged for missing preview")
    func environmentObjectPropertySuppressesMissingPreview() throws {
        let visitor = createVisitor(filePath: "Sources/DashboardView.swift")
        let source = """
        struct DashboardView: View {
            @EnvironmentObject var appState: AppState

            var body: some View {
                Text("Dashboard")
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let previewIssues = issues.filter { $0.ruleName == .missingPreview }
        #expect(previewIssues.isEmpty, "View with @EnvironmentObject should not be flagged for missing preview")
    }

    // MARK: - analyzeBodyForBasicErrorHandling via func body (lines 257-277)

    @Test("func body with Text Error but no alert flags basic error handling")
    func funcBodyTextErrorNoAlert() throws {
        let visitor = createVisitor(filePath: "test.swift")
        let source = """
        struct MyView: View {
            func body() -> some View {
                VStack {
                    Text("Error: something is wrong")
                }
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let errorIssues = issues.filter { $0.ruleName == .basicErrorHandling }
        #expect(errorIssues.count >= 1)
    }

    @Test("func body with Alert is not flagged")
    func funcBodyWithAlertConstructor() throws {
        let visitor = createVisitor(filePath: "test.swift")
        let source = """
        struct MyView: View {
            func body() -> some View {
                VStack {
                    if let error = someError {
                        Text("Error: happened")
                    }
                    Alert(title: Text("Oops"))
                }
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let errorIssues = issues.filter { $0.ruleName == .basicErrorHandling }
        #expect(errorIssues.isEmpty)
    }

    // MARK: - App struct does not trigger missing preview (line 29)

    @Test("App struct does not trigger missing preview")
    func appStructNoMissingPreview() throws {
        let visitor = createVisitor(filePath: "Sources/MyApp.swift")
        let source = """
        struct MyApp: App {
            var body: some Scene {
                WindowGroup {
                    ContentView()
                }
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let previewIssues = issues.filter { $0.ruleName == .missingPreview }
        #expect(previewIssues.isEmpty, "App struct should not be flagged for missing preview")
    }

    // MARK: - Binding fallback path (line 176, analyzeBindingFallback)

    @Test("body binding without accessor or initializer exercises fallback path")
    func bodyBindingFallbackPath() throws {
        let visitor = createVisitor(filePath: "test.swift")
        let source = """
        struct FallbackView: View {
            var body: some View {
                if let error = someError {
                    Text("Error: problem occurred")
                }
            }
        }
        """

        let issues = walkSource(source, visitor: visitor)
        let errorIssues = issues.filter { $0.ruleName == .basicErrorHandling }
        #expect(errorIssues.count >= 1)
    }
}
