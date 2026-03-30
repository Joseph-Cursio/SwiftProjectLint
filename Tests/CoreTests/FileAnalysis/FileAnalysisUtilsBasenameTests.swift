import Testing
import Foundation
@testable import Core
@testable import SwiftProjectLintRules

struct FileAnalysisUtilsBasenameTests {
    @Test(arguments: [
        ("/Users/test/Documents/file.swift", "file"),
        ("/a/b/c/d/e.swift", "e"),
        ("/tmp/complex.name.with.dots.swift", "complex.name.with.dots"),
        ("/Users/test/My File.swift", "My File"),
        ("/tmp/!@#$%^&*().swift", "!@#$%^&*()"),
        ("/archive/file.tar.gz", "file.tar.gz"),
        ("/Users/test/filename", "filename"),
        ("", "")
    ])
    func extractBasename(path: String, expected: String) {
        #expect(FileAnalysisUtils.extractSwiftBasename(from: path) == expected)
    }
}
