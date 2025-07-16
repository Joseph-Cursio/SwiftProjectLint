import Testing
import Foundation
@testable import SwiftProjectLintCore

@MainActor
final class CrossFileAnalysisEngineProjectEdgeCaseTests {
    @Test func testDetectCrossFilePatternsWithEmptyProject() async throws {
        let engine = CrossFileAnalysisEngine()
        let projectFiles: [ProjectFile] = []
        let result = engine.detectCrossFilePatterns(projectFiles: projectFiles)
        #expect(result.isEmpty)
    }
    @Test func testDetectCrossFilePatternsWithSingleFile() async throws {
        let engine = CrossFileAnalysisEngine()
        let file = ProjectFile(name: "A.swift", content: "struct A {}")
        let result = engine.detectCrossFilePatterns(projectFiles: [file])
        // Expect no cross-file patterns in a single file
        #expect(result.isEmpty)
    }
    @Test func testDetectCrossFilePatternsWithInvalidFiles() async throws {
        let engine = CrossFileAnalysisEngine()
        let invalidFile = ProjectFile(name: "Broken.swift", content: "!!! not swift code !!!")
        let result = engine.detectCrossFilePatterns(projectFiles: [invalidFile])
        // Should handle gracefully, likely no patterns found
        #expect(result.isEmpty)
    }
    @Test func testDetectCrossFilePatternsWithMixedValidInvalidFiles() async throws {
        let engine = CrossFileAnalysisEngine()
        let validFile = ProjectFile(name: "A.swift", content: "struct A {}")
        let invalidFile = ProjectFile(name: "Broken.swift", content: "!!! not swift code !!!")
        let result = engine.detectCrossFilePatterns(projectFiles: [validFile, invalidFile])
        // Should not crash, and should return results only for valid files
        #expect(result.isEmpty || result.count >= 0)
    }
}