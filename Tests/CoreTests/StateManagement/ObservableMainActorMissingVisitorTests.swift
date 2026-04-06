import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct ObservableMainActorMissingVisitorTests {

    private func makeVisitor() -> ObservableMainActorMissingVisitor {
        let pattern = ObservableMainActorMissing().pattern
        return ObservableMainActorMissingVisitor(pattern: pattern)
    }

    private func run(
        _ visitor: ObservableMainActorMissingVisitor,
        source: String,
        filePath: String = "test.swift"
    ) {
        let sourceFile = Parser.parse(source: source)
        visitor.setFilePath(filePath)
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: filePath, tree: sourceFile))
        visitor.walk(sourceFile)
    }

    // MARK: - Flagged

    @Test("Flags @Observable class without @MainActor")
    func detectsBasicViolation() throws {
        let source = """
        @Observable
        class CounterModel {
            var count = 0
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .observableMainActorMissing)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("CounterModel"))
    }

    @Test("Message contains the class name")
    func messageContainsTypeName() throws {
        let source = """
        @Observable
        class ProfileModel {
            var name = ""
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("ProfileModel"))
    }

    @Test("Flags multiple @Observable classes without @MainActor in one file")
    func detectsMultipleViolations() {
        let source = """
        @Observable
        class ModelA {
            var x = 0
        }

        @Observable
        class ModelB {
            var y = ""
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        #expect(visitor.detectedIssues.count == 2)
    }

    @Test("Flags @Observable class with many properties")
    func detectsClassWithManyProperties() throws {
        let source = """
        @Observable
        class SettingsModel {
            var isDarkMode = false
            var fontSize: Int = 14
            var username = ""
            var isLoggedIn = false
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

    @Test("No issue when @MainActor appears after @Observable")
    func noIssueWhenMainActorAfterObservable() {
        let source = """
        @Observable
        @MainActor
        class CounterModel {
            var count = 0
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for plain class without @Observable")
    func noIssueForPlainClass() {
        let source = """
        class PlainModel {
            var count = 0
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for ObservableObject conformers (separate rule covers those)")
    func noIssueForObservableObject() {
        let source = """
        class ViewModel: ObservableObject {
            @Published var count = 0
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for struct with @Observable")
    func noIssueForObservableStruct() {
        // @Observable can technically be applied to structs (though unusual) —
        // the rule targets classes only, where actor isolation matters.
        let source = """
        @Observable
        struct Config {
            var value = 0
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("Only flags the violating class, not the safe sibling")
    func onlyFlagsViolatingClass() {
        let source = """
        @MainActor
        @Observable
        class SafeModel {
            var x = 0
        }

        @Observable
        class UnsafeModel {
            var y = 0
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues[0].message.contains("UnsafeModel"))
    }

    // MARK: - Cross-File Suppression

    @Test("Suppresses when superclass is @MainActor-annotated in same file")
    func suppressesWhenSuperclassIsMainActor() {
        let source = """
        @MainActor
        @Observable
        class BaseModel {}

        @Observable
        class DerivedModel: BaseModel {
            var count = 0
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        visitor.finalizeAnalysis()

        // DerivedModel inherits @MainActor from BaseModel — suppressed
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("Suppresses cross-file: @MainActor superclass in different file")
    func suppressesCrossFileInheritance() {
        let baseSource = """
        @MainActor
        @Observable
        class BaseModel {}
        """
        let derivedSource = """
        @Observable
        class DerivedModel: BaseModel {
            var count = 0
        }
        """

        let baseFile = Parser.parse(source: baseSource)
        let derivedFile = Parser.parse(source: derivedSource)
        let fileCache: [String: SourceFileSyntax] = [
            "Base.swift": baseFile,
            "Derived.swift": derivedFile
        ]

        let pattern = ObservableMainActorMissing().pattern
        let visitor = ObservableMainActorMissingVisitor(fileCache: fileCache)
        visitor.setPattern(pattern)

        for (fileName, sourceFile) in fileCache {
            visitor.setFilePath(fileName)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: fileName, tree: sourceFile))
            visitor.walk(sourceFile)
        }
        visitor.finalizeAnalysis()

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("Does not suppress when superclass also lacks @MainActor")
    func doesNotSuppressWhenSuperclassLacksMainActor() {
        let baseSource = """
        @Observable
        class BaseModel {
            var shared = ""
        }
        """
        let derivedSource = """
        @Observable
        class DerivedModel: BaseModel {
            var count = 0
        }
        """

        let baseFile = Parser.parse(source: baseSource)
        let derivedFile = Parser.parse(source: derivedSource)
        let fileCache: [String: SourceFileSyntax] = [
            "Base.swift": baseFile,
            "Derived.swift": derivedFile
        ]

        let pattern = ObservableMainActorMissing().pattern
        let visitor = ObservableMainActorMissingVisitor(fileCache: fileCache)
        visitor.setPattern(pattern)

        for (fileName, sourceFile) in fileCache {
            visitor.setFilePath(fileName)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: fileName, tree: sourceFile))
            visitor.walk(sourceFile)
        }
        visitor.finalizeAnalysis()

        // Both classes are @Observable without @MainActor — both flagged
        #expect(visitor.detectedIssues.count == 2)
    }
}
