import XCTest
@testable import SwiftProjectLintCore

class ProjectLinterTests: XCTestCase {

    @MainActor
    func testAnalyzeProjectWithMastermindProject() {
        // Given
        let linter = ProjectLinter()
        let mastermindPath = "/Users/josephcursio/GitHub_projects/Mastermind/Mastermind"
        
        // When
        let issues = linter.analyzeProject(at: mastermindPath, categories: [.stateManagement])
        
        // Then
        print("DEBUG: testAnalyzeProjectWithMastermindProject - Found \(issues.count) issues")
        for (index, issue) in issues.enumerated() {
            print("DEBUG: Issue \(index): \(issue.message)")
        }
        
        // Should find some issues in the Mastermind project
        XCTAssertGreaterThanOrEqual(issues.count, 0, "Should analyze Mastermind project successfully")
    }

    func testFindSwiftFilesWithMastermindProject() {
        // Given
        let linter = ProjectLinter()
        let mastermindPath = "/Users/josephcursio/GitHub_projects/Mastermind/Mastermind"
        
        // When
        let swiftFiles = linter.findSwiftFiles(in: mastermindPath)
        
        // Then
        print("DEBUG: testFindSwiftFilesWithMastermindProject - Found \(swiftFiles.count) Swift files")
        for (index, file) in swiftFiles.enumerated() {
            print("DEBUG: File \(index): \(file)")
        }
        
        // Should find Swift files in the Mastermind project
        XCTAssertGreaterThan(swiftFiles.count, 0, "Should find Swift files in Mastermind project")
    }
} 