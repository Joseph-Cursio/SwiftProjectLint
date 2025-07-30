import Testing
import Foundation
@testable import SwiftProjectLintCore

@MainActor
final class SimpleExtractBasenameTest {
    
    @Test func testExtractBasenameNoPath() async throws {
        // Arrange: Set up a typical file path
        let justFilename = "HomeView.swift"

        // Act: Extract the view name using the utility function
        let filenameResult = FileAnalysisUtils.extractSwiftBasename(from: justFilename)

        // Assert: Verify the function correctly extracts the basename
        #expect(filenameResult == "HomeView")
    }

    @Test func testExtractBasenameWithPath() async throws {
        // Arrange: Set up a typical file path
        let filePath = "/Users/developer/MyProject/Views/ContentView.swift"
        
        // Act: Extract the view name using the utility function
        let result = FileAnalysisUtils.extractSwiftBasename(from: filePath)
        
        // Assert: Verify the function correctly extracts the basename
        #expect(result == "ContentView")

    }

    // jdc: I never checked for Windows pathname formats, by CoPilot added this test...
    @Test func testExtractWindowsBasenamePath() async throws {
        
        // Arrange: Set up a typical file path
        let windowsPath = "C:\\Projects\\SwiftUI\\DetailView.swift"

        // Act: Extract the view name using the utility function
        let windowsResult = FileAnalysisUtils.extractSwiftBasename(from: windowsPath)

        // Assert: Verify the function correctly extracts the basename
        #expect(windowsResult == "DetailView")
 
        let justFilename = "HomeView.swift"
        let filenameResult = FileAnalysisUtils.extractSwiftBasename(from: justFilename)
        #expect(filenameResult == "HomeView")
    }
}
