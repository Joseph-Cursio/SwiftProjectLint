@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct UnabstractedFileIOVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "SourceFile.swift"
    ) -> [LintIssue] {
        let visitor = UnabstractedFileIOVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .unabstractedFileIO }
    }

    // MARK: - Positive cases

    @Test func testFlagsContentsOfFileReadInsideModel() throws {
        let source = """
        final class ImpactModel {
            func ruleDiff(filePath: String) -> String {
                guard let source = try? String(contentsOfFile: filePath, encoding: .utf8) else { return "" }
                return source
            }
        }
        """
        let issues = analyzeSource(source)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("ImpactModel"))
        #expect(issue.message.contains("String(contentsOfFile:)"))
    }

    @Test func testFlagsContentsOfReadInsideViewModel() {
        let source = """
        final class EditorViewModel {
            func load(url: URL) {
                let text = try? String(contentsOf: url, encoding: .utf8)
                _ = text
            }
        }
        """
        #expect(analyzeSource(source).count == 1)
    }

    @Test func testFlagsDataContentsOfInsideService() {
        let source = """
        struct ReportService {
            func read(url: URL) -> Data? {
                try? Data(contentsOf: url)
            }
        }
        """
        #expect(analyzeSource(source).count == 1)
    }

    @Test func testFlagsWriteToInsideModel() {
        let source = """
        final class ConfigModel {
            func save(text: String, url: URL) throws {
                try text.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        """
        #expect(analyzeSource(source).count == 1)
    }

    // MARK: - Negative cases (precision)

    @Test func testIgnoresRawIOInsideReaderSeam() {
        // The seam type itself is *supposed* to do raw I/O — don't nag it.
        let source = """
        struct FileSystemSourceReader {
            func readSource(at path: String) throws -> String {
                try String(contentsOfFile: path, encoding: .utf8)
            }
        }
        """
        #expect(analyzeSource(source).isEmpty)
    }

    @Test func testIgnoresRawIOInsideActor() {
        let source = """
        actor SwiftFormatCLIActor {
            func run(path: String) throws -> String {
                try String(contentsOfFile: path, encoding: .utf8)
            }
        }
        """
        #expect(analyzeSource(source).isEmpty)
    }

    @Test func testIgnoresRawIOInTestFile() {
        let source = """
        final class ImpactModel {
            func load(path: String) -> String? {
                try? String(contentsOfFile: path, encoding: .utf8)
            }
        }
        """
        #expect(analyzeSource(source, filePath: "ImpactModelTests.swift").isEmpty)
    }

    @Test func testIgnoresWriteThroughInjectedSeamHelper() {
        // `SafeFileWriter.write(text, to:)` is already a seam — the content is the
        // unlabeled first arg, so it must not be mistaken for `String.write(to:)`.
        let source = """
        final class ConfigModel {
            func save(text: String, url: URL) throws {
                try SafeFileWriter.write(text, to: url, createBackup: true)
            }
        }
        """
        #expect(analyzeSource(source).isEmpty)
    }

    @Test func testIgnoresNonIOWriteCall() {
        // `.write(to:)` is required, but a model calling its own injected seam
        // (no Foundation read initializer) shouldn't be the read path. A plain
        // String initializer that isn't a contents read must not fire.
        let source = """
        final class ImpactModel {
            func make() -> String {
                String("hello")
            }
        }
        """
        #expect(analyzeSource(source).isEmpty)
    }
}
