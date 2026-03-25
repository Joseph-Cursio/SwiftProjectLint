import Testing
import Foundation
@testable import Core

struct SimpleExtractBasenameTest {
    
    // swiftprojectlint:disable Test Missing Require
    @Test func testExtractBasenameNoPath() throws {
        // Arrange: Set up a typical file path
        let justFilename = "HomeView.swift"

        // Act: Extract the view name using the utility function
        let filenameResult = FileAnalysisUtils.extractSwiftBasename(from: justFilename)

        // Assert: Verify the function correctly extracts the basename
        #expect(filenameResult == "HomeView")
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testExtractBasenameWithPath() throws {
        // Arrange: Set up a typical file path
        let filePath = "/Users/developer/MyProject/Views/ContentView.swift"
        
        // Act: Extract the view name using the utility function
        let result = FileAnalysisUtils.extractSwiftBasename(from: filePath)
        
        // Assert: Verify the function correctly extracts the basename
        #expect(result == "ContentView")

    }

    // jdc: I never checked for Windows pathname formats, by CoPilot added this test...
    // swiftprojectlint:disable Test Missing Require
    @Test func testExtractWindowsBasenamePath() throws {
        
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
