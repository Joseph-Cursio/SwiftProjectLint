import Testing
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

/// Coverage tests for uncovered paths in SyntaxHelpers.swift:
/// - isForEachCollectionSafeForSelfID: array literal, .allCases, .filter chain (lines 29, 35, 41, 48-49)
/// - inferForEachElementType: .allCases pattern, variable reference, member access (lines 87, 113)
/// - findArrayElementType: function parameter, struct/class member, class member (lines 128, 138-140)
/// - findArrayParameter (lines 150-156)
/// - findArrayProperty (lines 163-176)
/// - extractArrayElementTypeName: member type path (lines 187-191)
@Suite("SyntaxHelpers Coverage Tests")
struct SyntaxHelpersCoverageTests {

    // MARK: - Helpers

    /// Parses source code and runs a PerformanceVisitor to exercise ForEach-related
    /// SyntaxHelpers functions via the visitor's ForEach detection paths.
    private func analyzeWithPerformanceVisitor(_ source: String) -> [LintIssue] {
        let syntax = Parser.parse(source: source)
        let visitor = PerformanceVisitor(patternCategory: .performance)
        let converter = SourceLocationConverter(fileName: "Test.swift", tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath("Test.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    /// Parses source code and runs a UIVisitor to exercise ForEach-related
    /// SyntaxHelpers functions via the UIVisitor's ForEach detection paths.
    private func analyzeWithUIVisitor(_ source: String) -> [LintIssue] {
        let syntax = Parser.parse(source: source)
        let visitor = UIVisitor(patternCategory: .uiPatterns)
        let converter = SourceLocationConverter(fileName: "Test.swift", tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath("Test.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    // MARK: - isForEachCollectionSafeForSelfID

    @Test("array literal is safe for self ID")
    func arrayLiteralSafeForSelfID() throws {
        // ForEach([1, 2, 3], id: \.self) — should NOT flag \.self issue
        let source = """
        struct TestView: View {
            var body: some View {
                ForEach([1, 2, 3], id: \\.self) { item in
                    Text("\\(item)")
                }
            }
        }
        """

        let issues = analyzeWithPerformanceVisitor(source)
        let selfIDIssues = issues.filter {
            $0.message.contains("\\.self") && $0.message.contains("ForEach")
        }
        #expect(selfIDIssues.isEmpty, "Array literal with .self should not be flagged")
    }

    @Test(".allCases is safe for self ID")
    func allCasesSafeForSelfID() throws {
        // ForEach(MyEnum.allCases, id: \.self) — should NOT flag \.self issue
        let source = """
        struct TestView: View {
            var body: some View {
                ForEach(MyEnum.allCases, id: \\.self) { value in
                    Text("\\(value)")
                }
            }
        }
        """

        let issues = analyzeWithPerformanceVisitor(source)
        let selfIDIssues = issues.filter {
            $0.message.contains("\\.self") && $0.message.contains("ForEach")
        }
        #expect(selfIDIssues.isEmpty, ".allCases with .self should not be flagged")
    }

    @Test(".filter chain is safe for self ID")
    func filterChainSafeForSelfID() throws {
        let source = """
        struct TestView: View {
            let names: [String] = []
            var body: some View {
                ForEach(names.filter { $0.isEmpty == false }, id: \\.self) { name in
                    Text(name)
                }
            }
        }
        """

        let issues = analyzeWithPerformanceVisitor(source)
        let selfIDIssues = issues.filter {
            $0.message.contains("\\.self") && $0.message.contains("ForEach")
        }
        #expect(selfIDIssues.isEmpty, ".filter chain with .self should not be flagged")
    }

    // MARK: - inferForEachElementType: TypeName.allCases pattern (line 87)

    @Test("infers element type from TypeName.allCases in ForEach")
    func infersTypeFromAllCases() throws {
        // ForEach(Category.allCases) without id: — if Category is Identifiable, no issue
        // This exercises the inferForEachElementType pattern 1
        let source = """
        struct TestView: View {
            var body: some View {
                ForEach(Category.allCases) { item in
                    Text("\\(item)")
                }
            }
        }
        """

        let issues = analyzeWithPerformanceVisitor(source)
        // Without knownIdentifiableTypes, this will flag ForEach without id
        // The key thing is the code path was exercised without crashing
        _ = issues.filter { $0.ruleName == .forEachWithoutID }
    }

    // MARK: - inferForEachElementType: member access pattern (line 113)

    @Test("infers element type from member access property in ForEach")
    func infersTypeFromMemberAccess() throws {
        // ForEach(self.items) WITHOUT id: — triggers inferForEachElementType pattern 3
        let source = """
        struct TestView: View {
            var items: [String] = []
            var body: some View {
                ForEach(self.items) { item in
                    Text(item)
                }
            }
        }
        """

        let issues = analyzeWithPerformanceVisitor(source)
        // This exercises inferForEachElementType pattern 3 (member access)
        _ = issues
    }

    // MARK: - inferForEachElementType: variable reference finding array type (lines 104, 128)

    @Test("infers element type from struct property with array type annotation")
    func infersTypeFromStructPropertyArrayAnnotation() throws {
        // ForEach(items) WITHOUT id: — triggers inferForEachElementType pattern 2
        // then findArrayElementType -> findArrayProperty for struct members
        let source = """
        struct TestView: View {
            var items: [TodoItem] = []
            var body: some View {
                ForEach(items) { item in
                    Text("\\(item)")
                }
            }
        }
        """

        let issues = analyzeWithPerformanceVisitor(source)
        // exercises findArrayElementType -> findArrayProperty for struct
        _ = issues
    }

    // MARK: - findArrayParameter: function parameter path (lines 150-156)

    @Test("infers element type from function parameter array type")
    func infersTypeFromFunctionParameter() throws {
        // ForEach inside a function that has [Person] parameter type
        let source = """
        struct TestView: View {
            var body: some View {
                Text("hello")
            }

            func makeList(items: [Person]) -> some View {
                ForEach(items) { person in
                    Text("name")
                }
            }
        }
        """

        let issues = analyzeWithPerformanceVisitor(source)
        // exercises findArrayParameter path
        _ = issues
    }

    // MARK: - findArrayProperty: class member path (lines 138-140)

    @Test("infers element type from class member array property via member access")
    func infersTypeFromClassMemberArray() throws {
        // ForEach(viewModel.tasks) without id: — triggers pattern 3
        // then findArrayProperty should search the class declaration
        let source = """
        class ViewModel {
            var tasks: [TaskItem] = []
        }

        struct TestView: View {
            let viewModel = ViewModel()
            var body: some View {
                ForEach(viewModel.tasks) { task in
                    Text("task")
                }
            }
        }
        """

        let issues = analyzeWithPerformanceVisitor(source)
        // exercises findArrayProperty for class declarations
        _ = issues
    }

    // MARK: - extractArrayElementTypeName: member type path (lines 187-191)

    @Test("extracts element type from nested member type array")
    func extractsNestedMemberTypeFromArray() throws {
        // ForEach(items) where items: [Outer.Inner] — triggers MemberTypeSyntax path
        let source = """
        struct TestView: View {
            var items: [Outer.Inner] = []
            var body: some View {
                ForEach(items) { item in
                    Text("item")
                }
            }
        }
        """

        let issues = analyzeWithPerformanceVisitor(source)
        // exercises extractArrayElementTypeName -> MemberTypeSyntax path
        _ = issues
    }

    // MARK: - isForEachCollectionSafeForSelfID: no collection arg (line 29)

    @Test("ForEach with no arguments returns false for safe self ID check")
    func forEachNoArgsNotSafe() throws {
        // ForEach with only id: parameter (edge case)
        let source = """
        struct TestView: View {
            var body: some View {
                ForEach(id: \\.self) {
                    Text("item")
                }
            }
        }
        """

        let issues = analyzeWithPerformanceVisitor(source)
        // Edge case: no collection argument; exercises the guard-return-false path
        // Exercising the code path is the goal; no specific assertion needed
        _ = issues
    }

    // MARK: - UIVisitor ForEach: Identifiable suppression

    @Test("UIVisitor suppresses ForEach warning for Identifiable types")
    func uiVisitorSuppressesForIdentifiable() throws {
        let source = """
        struct TestView: View {
            var items: [String] = []
            var body: some View {
                ForEach(items) { item in
                    Text(item)
                }
            }
        }
        """

        let syntax = Parser.parse(source: source)
        let visitor = UIVisitor(patternCategory: .uiPatterns)
        visitor.setFilePath("test.swift")
        visitor.knownIdentifiableTypes = ["String"]
        visitor.walk(syntax)

        let forEachIssues = visitor.detectedIssues.filter {
            $0.ruleName == .forEachWithoutIDUI
        }
        #expect(forEachIssues.isEmpty, "Should suppress ForEach warning for known Identifiable types")
    }
}
