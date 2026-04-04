import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct MainActorMissingVisitorTests {

    private func makeVisitor() -> MainActorMissingVisitor {
        let pattern = MainActorMissing().pattern
        return MainActorMissingVisitor(pattern: pattern)
    }

    private func run(_ visitor: MainActorMissingVisitor, source: String, filePath: String = "test.swift") {
        let sourceFile = Parser.parse(source: source)
        visitor.setFilePath(filePath)
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: filePath, tree: sourceFile))
        visitor.walk(sourceFile)
    }

    // MARK: - Flagged

    @Test("Flags ObservableObject class with @Published property missing @MainActor")
    func detectsBasicViolation() throws {
        let source = """
        class CounterViewModel: ObservableObject {
            @Published var count = 0
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .mainActorMissingOnUICode)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("CounterViewModel"))
    }

    @Test("Message contains the class name")
    func messageContainsTypeName() throws {
        let source = """
        class ProfileViewModel: ObservableObject {
            @Published var name = ""
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("ProfileViewModel"))
        #expect(issue.message.contains("ObservableObject"))
    }

    @Test("Flags multiple violating classes in one file")
    func detectsMultipleViolations() {
        let source = """
        class ViewModelA: ObservableObject {
            @Published var x = 0
        }
        class ViewModelB: ObservableObject {
            @Published var y = ""
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        #expect(visitor.detectedIssues.count == 2)
    }

    @Test("Flags class with multiple @Published properties")
    func detectsMultiplePublishedProperties() throws {
        let source = """
        class SettingsViewModel: ObservableObject {
            @Published var isDarkMode = false
            @Published var fontSize: Int = 14
            @Published var username = ""
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Not Flagged

    @Test("No issue when @MainActor is present")
    func noIssueWhenMainActorPresent() {
        let source = """
        @MainActor
        class CounterViewModel: ObservableObject {
            @Published var count = 0
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue when no @Published properties")
    func noIssueWithoutPublishedProperties() {
        let source = """
        class DataService: ObservableObject {
            var items: [String] = []
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for non-ObservableObject class with @Published")
    func noIssueForNonObservableObject() {
        let source = """
        class PlainClass {
            @Published var value = 0
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for @Observable macro types (not ObservableObject)")
    func noIssueForObservableMacro() {
        let source = """
        @Observable
        class CounterModel {
            var count = 0
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for structs (cannot conform to ObservableObject as base type)")
    func noIssueForStructs() {
        let source = """
        struct Config: ObservableObject {
            @Published var value = 0
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for enums")
    func noIssueForEnums() {
        let source = """
        enum State: ObservableObject {
            @Published var value = 0
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Cross-File Suppression

    @Test("Suppresses when superclass is @MainActor-annotated in same file")
    func suppressesWhenSuperclassIsMainActor() {
        let source = """
        @MainActor
        class BaseViewModel: ObservableObject {}

        class DerivedViewModel: BaseViewModel {
            @Published var count = 0
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        // DerivedViewModel inherits @MainActor from BaseViewModel — should be suppressed
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("Suppresses cross-file: superclass @MainActor in different file")
    func suppressesCrossFileInheritance() {
        let baseSource = """
        @MainActor
        class BaseViewModel: ObservableObject {}
        """
        let derivedSource = """
        class DerivedViewModel: BaseViewModel {
            @Published var count = 0
        }
        """

        let baseFile = Parser.parse(source: baseSource)
        let derivedFile = Parser.parse(source: derivedSource)
        let fileCache: [String: SourceFileSyntax] = [
            "Base.swift": baseFile,
            "Derived.swift": derivedFile
        ]

        let pattern = MainActorMissing().pattern
        let visitor = MainActorMissingVisitor(fileCache: fileCache)
        visitor.setPattern(pattern)

        for (fileName, sourceFile) in fileCache {
            visitor.setFilePath(fileName)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: fileName, tree: sourceFile))
            visitor.walk(sourceFile)
        }
        visitor.finalizeAnalysis()

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("Does not suppress direct ObservableObject conformer when it lacks @MainActor")
    func doesNotSuppressNonMainActorBase() {
        let baseSource = """
        class BaseViewModel: ObservableObject {
            @Published var shared = ""
        }
        """
        let derivedSource = """
        class DerivedViewModel: BaseViewModel {
            @Published var count = 0
        }
        """

        let baseFile = Parser.parse(source: baseSource)
        let derivedFile = Parser.parse(source: derivedSource)
        let fileCache: [String: SourceFileSyntax] = [
            "Base.swift": baseFile,
            "Derived.swift": derivedFile
        ]

        let pattern = MainActorMissing().pattern
        let visitor = MainActorMissingVisitor(fileCache: fileCache)
        visitor.setPattern(pattern)

        for (fileName, sourceFile) in fileCache {
            visitor.setFilePath(fileName)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: fileName, tree: sourceFile))
            visitor.walk(sourceFile)
        }
        visitor.finalizeAnalysis()

        // BaseViewModel is a direct ObservableObject conformer without @MainActor — flagged.
        // DerivedViewModel does not list ObservableObject in its own clause; transitive
        // conformance through inheritance is not resolved from AST alone, so it is not flagged.
        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues[0].message.contains("BaseViewModel"))
    }

    @Test("Flags standalone class, does not flag @MainActor sibling")
    func onlyFlagsViolatingClass() {
        let source = """
        @MainActor
        class SafeViewModel: ObservableObject {
            @Published var x = 0
        }

        class UnsafeViewModel: ObservableObject {
            @Published var y = 0
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues[0].message.contains("UnsafeViewModel"))
    }
}
