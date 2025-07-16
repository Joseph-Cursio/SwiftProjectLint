import Testing
import Foundation
@testable import SwiftProjectLintCore

@MainActor
final class FileAnalysisUtilsFindSwiftFilesTests {
    
    @Test func testFindSwiftFilesWithValidDirectory() async throws {
        // Create a temporary test directory structure
        let tempDir = createTempTestDirectory()
        defer { cleanupTempDirectory(tempDir) }
        
        // Test the findSwiftFiles function
        let foundFiles = FileAnalysisUtils.findSwiftFiles(in: tempDir)
        
        // Verify we found the expected Swift files
        #expect(foundFiles.count == 4)
        
        // Check that all found files end with .swift
        for file in foundFiles {
            #expect(file.hasSuffix(".swift"))
        }
        
        // Check specific files are found (convert to basenames for easier comparison)
        let basenames = foundFiles.map { (($0 as NSString).lastPathComponent) }
        #expect(basenames.contains("ContentView.swift"))
        #expect(basenames.contains("DetailView.swift"))
        #expect(basenames.contains("SettingsView.swift"))
        #expect(basenames.contains("NestedView.swift"))
        
        // Verify non-Swift files are not included
        #expect(!basenames.contains("README.md"))
        #expect(!basenames.contains("config.json"))
    }
    
    @Test func testFindSwiftFilesWithNestedStructure() async throws {
        // ... existing code ...
    }
    
    @Test func testFindSwiftFilesWithEmptyDirectory() async throws {
        let tempDir = createEmptyTempDirectory()
        defer { cleanupTempDirectory(tempDir) }
        
        let foundFiles = FileAnalysisUtils.findSwiftFiles(in: tempDir)
        
        #expect(foundFiles.isEmpty)
    }
    
    @Test func testFindSwiftFilesWithNonSwiftFiles() async throws {
        // ... existing code ...
    }
    
    @Test func testFindSwiftFilesWithNonExistentDirectory() async throws {
        let nonExistentPath = "/this/path/does/not/exist"
        
        let foundFiles = FileAnalysisUtils.findSwiftFiles(in: nonExistentPath)
        
        #expect(foundFiles.isEmpty)
    }
    
    @Test func testFindSwiftFilesWithFileInsteadOfDirectory() async throws {
        // ... existing code ...
    }
    @Test func testFindSwiftFilesWithHiddenFiles() async throws {
        // ... existing code ...
    }
    @Test func testFindSwiftFilesWithLargeProject() async throws {
        // ... existing code ...
    }
    @Test func testFindSwiftFilesWithSpecialCharacters() async throws {
        // ... existing code ...
    }
    
    // MARK: - Helper Methods
    
    private func createTempTestDirectory() -> String {
        let tempDir = NSTemporaryDirectory() + "SwiftProjectLintTest_" + UUID().uuidString
        let fileManager = FileManager.default
        
        // Create main directory
        try! fileManager.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        
        // Create subdirectories
        let viewsDir = (tempDir as NSString).appendingPathComponent("Views")
        let modelsDir = (tempDir as NSString).appendingPathComponent("Models")
        let nestedDir = (viewsDir as NSString).appendingPathComponent("Nested")
        
        try! fileManager.createDirectory(atPath: viewsDir, withIntermediateDirectories: true)
        try! fileManager.createDirectory(atPath: modelsDir, withIntermediateDirectories: true)
        try! fileManager.createDirectory(atPath: nestedDir, withIntermediateDirectories: true)
        
        // Create Swift files
        let swiftFiles = [
            (tempDir as NSString).appendingPathComponent("ContentView.swift"),
            (viewsDir as NSString).appendingPathComponent("DetailView.swift"),
            (modelsDir as NSString).appendingPathComponent("SettingsView.swift"),
            (nestedDir as NSString).appendingPathComponent("NestedView.swift")
        ]
        
        for filePath in swiftFiles {
            let content = """
            import SwiftUI
            
            struct \(FileAnalysisUtils.extractSwiftBasename(from: filePath)): View {
                var body: some View {
                    Text("Hello from \(FileAnalysisUtils.extractSwiftBasename(from: filePath))")
                }
            }
            """
            try! content.write(toFile: filePath, atomically: true, encoding: .utf8)
        }
        
        // Create non-Swift files (should be ignored)
        let nonSwiftFiles = [
            (tempDir as NSString).appendingPathComponent("README.md"),
            (viewsDir as NSString).appendingPathComponent("config.json"),
            (modelsDir as NSString).appendingPathComponent("notes.txt")
        ]
        
        for filePath in nonSwiftFiles {
            try! "Test content".write(toFile: filePath, atomically: true, encoding: .utf8)
        }
        
        return tempDir
    }
    
    private func createEmptyTempDirectory() -> String {
        let tempDir = NSTemporaryDirectory() + "SwiftProjectLintEmpty_" + UUID().uuidString
        try! FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    private func cleanupTempDirectory(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}
