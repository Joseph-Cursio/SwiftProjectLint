import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct ViewModelDirectDBAccessVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = ViewModelDirectDBAccessVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = ViewModelDirectDBAccessVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .viewModelDirectDBAccess }
    }

    // MARK: - Positive: flags view models importing persistence

    @Test func testFlagsObservableObjectWithSwiftData() throws {
        let source = """
        import SwiftData

        class TaskListViewModel: ObservableObject {
            var modelContext: ModelContext
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("TaskListViewModel"))
        #expect(issue.message.contains("SwiftData"))
    }

    @Test func testFlagsObservableWithCoreData() throws {
        let source = """
        import CoreData

        @Observable
        class ItemViewModel {
            var context: NSManagedObjectContext
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("CoreData") == true)
    }

    @Test func testFlagsNameBasedViewModel() throws {
        let source = """
        import SwiftData

        class TaskVM {
            var modelContext: ModelContext
        }
        """
        // TaskVM doesn't conform to ObservableObject but name ends in VM
        // However, it's not a class with ObservableObject or @Observable
        // Actually the visitor checks name ending in VM too
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueWithoutPersistenceImport() throws {
        let source = """
        import Foundation

        class TaskListViewModel: ObservableObject {
            @Published var items: [String] = []
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForRepositoryClass() throws {
        let source = """
        import SwiftData

        class TaskRepository {
            var modelContext: ModelContext
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForServiceFile() throws {
        let source = """
        import CoreData

        class DataManager: ObservableObject {
            var context: NSManagedObjectContext
        }
        """
        let issues = filteredIssues(source, filePath: "DataService.swift")
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForStoreClass() throws {
        let source = """
        import SwiftData

        @Observable
        class TaskStore {
            var modelContext: ModelContext
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForPlainClassWithImport() throws {
        let source = """
        import SwiftData

        class TaskHelper {
            func doWork() { }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}
