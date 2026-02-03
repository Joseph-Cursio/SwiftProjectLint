import Testing
import Foundation
@testable import SwiftProjectLintCore

@MainActor
final class FileAnalysisUtilsBasenameTests {
    @Test func testExtractBasenameWithValidPath() throws {
        let path = "/Users/test/Documents/file.swift"
        let result = FileAnalysisUtils.extractSwiftBasename(from: path)
        #expect(result == "file")
    }
    @Test func testExtractBasenameWithNestedPath() throws {
        let path = "/a/b/c/d/e.swift"
        let result = FileAnalysisUtils.extractSwiftBasename(from: path)
        #expect(result == "e")
    }
    @Test func testExtractBasenameWithComplexPath() throws {
        let path = "/tmp/complex.name.with.dots.swift"
        let result = FileAnalysisUtils.extractSwiftBasename(from: path)
        #expect(result == "complex.name.with.dots")
    }
    @Test func testExtractBasenameWithSpaces() throws {
        let path = "/Users/test/My File.swift"
        let result = FileAnalysisUtils.extractSwiftBasename(from: path)
        #expect(result == "My File")
    }
    @Test func testExtractbasenameWithSpecialCharacters() throws {
        let path = "/tmp/!@#$%^&*().swift"
        let result = FileAnalysisUtils.extractSwiftBasename(from: path)
        #expect(result == "!@#$%^&*()")
    }
    @Test func testExtractBasenameWithMultipleExtensions() throws {
        let path = "/archive/file.tar.gz"
        let result = FileAnalysisUtils.extractSwiftBasename(from: path)
        #expect(result == "file.tar.gz")
    }
    @Test func testExtractBasenameWithNoExtension() throws {
        let path = "/Users/test/filename"
        let result = FileAnalysisUtils.extractSwiftBasename(from: path)
        #expect(result == "filename")
    }
    @Test func testExtractBasenameWithEmptyPath() throws {
        let path = ""
        let result = FileAnalysisUtils.extractSwiftBasename(from: path)
        #expect(result.isEmpty)
    }
}
