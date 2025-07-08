//
//  SwiftProjectLintUITests.swift
//  SwiftProjectLintUITests
//
//  Created by Joseph Cursio on 7/1/25.
//

import XCTest

final class SwiftProjectLintUITests: XCTestCase {
    
    private var app: XCUIApplication!
    private var testDirectories: [String] = []

    override func setUpWithError() throws {
        // Ensure test isolation by using unique test identifiers
        let testID = UUID().uuidString
        UserDefaults.standard.set(testID, forKey: "testRunID")

        // Create a fresh app instance for each test
        app = XCUIApplication()
        app.launchArguments = ["--reset-userdefaults", "--test-run-id=\(testID)"]

        // Stop immediately when a failure occurs
        continueAfterFailure = false

        // Set initial state required for tests
        app.launch()
    }

    override func tearDownWithError() throws {
        // Clean up test directories
        for directory in testDirectories {
            try? FileManager.default.removeItem(atPath: directory)
        }
        testDirectories.removeAll()

        // Reset app reference
        app = nil
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let performanceApp = XCUIApplication()
            performanceApp.launch()
        }
    }
    
    // MARK: - Rule Filtering Tests
    
    /// This test verifies that the main UI elements are visible and the app launches correctly
    @MainActor
    func testMainUIElementsAreVisible() throws {
        // Launch app with fresh state
        app.launch()
        
        // Wait for app to be ready
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should be running in foreground")
        
        // Activate the app window
        app.activate()
        
        // Wait a bit more for UI to fully render
        Thread.sleep(forTimeInterval: 3.0)
        
        // Step 1: Verify the main title is visible
        let titleText = app.staticTexts["Swift Project Linter"]
        XCTAssertTrue(titleText.waitForExistence(timeout: 10), "Main title should be visible")
        
        // Step 2: Verify the description text is visible
        let descriptionText = app.staticTexts["Detect cross-file issues and architectural problems"]
        XCTAssertTrue(descriptionText.waitForExistence(timeout: 10), "Description text should be visible")
        
        // Step 3: Verify the Select Rules button is visible using accessibility label
        let selectRulesButton = app.buttons["Select Rules"]
        XCTAssertTrue(selectRulesButton.waitForExistence(timeout: 10), "Select Rules button should be visible")
        
        // Step 4: Verify the main action button is visible using accessibility label
        let mainActionButton = app.buttons["Run Project Analysis by Selecting a Folder..."]
        XCTAssertTrue(mainActionButton.waitForExistence(timeout: 10), "Main action button should be visible")
        
        // Step 5: Test that the Select Rules button is interactive
        selectRulesButton.tap()
        
        // Step 6: Wait for rule selector to appear
        let ruleSelector = app.sheets.firstMatch
        XCTAssertTrue(ruleSelector.waitForExistence(timeout: 5), "Rule selector should appear")
        
        // Step 7: Cancel the dialog
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "Cancel button should be visible")
        cancelButton.tap()
        
        XCTAssertFalse(ruleSelector.waitForExistence(timeout: 5), "Rule selector should dismiss")
    }
    
    /// This test verifies the rule selection UI works correctly
    @MainActor
    func testRuleSelectionUI() throws {
        // Launch app with fresh state
        app.launch()
        
        // Wait for app to be ready
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should be running in foreground")
        
        // Activate the app window
        app.activate()
        
        // Wait a bit more for UI to fully render
        Thread.sleep(forTimeInterval: 3.0)
        
        // Step 1: Open rule selector
        let selectRulesButton = app.buttons["Select Rules"]
        XCTAssertTrue(selectRulesButton.waitForExistence(timeout: 10), "Select Rules button should be visible")
        selectRulesButton.tap()
        
        let ruleSelector = app.sheets.firstMatch
        XCTAssertTrue(ruleSelector.waitForExistence(timeout: 5), "Rule selector should appear")
        
        // Step 2: Test Select All functionality
        let selectAllButton = app.buttons["Select All"]
        XCTAssertTrue(selectAllButton.waitForExistence(timeout: 5), "Select All button should be visible")
        selectAllButton.tap()
        
        // Step 3: Test Reset to Default functionality
        let resetButton = app.buttons["Reset to Default"]
        XCTAssertTrue(resetButton.waitForExistence(timeout: 5), "Reset to Default button should be visible")
        resetButton.tap()
        
        // Step 4: Cancel the dialog
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "Cancel button should be visible")
        cancelButton.tap()
        
        XCTAssertFalse(ruleSelector.waitForExistence(timeout: 5), "Rule selector should dismiss")
        
        // Step 5: Verify the main action button is still visible after canceling
        let mainActionButton = app.buttons["Run Project Analysis by Selecting a Folder..."]
        XCTAssertTrue(mainActionButton.waitForExistence(timeout: 10), "Main action button should still be visible after canceling rule selection")
    }
    
    /// This test verifies that the main action button is interactive
    @MainActor
    func testMainActionButtonIsInteractive() throws {
        // Launch app with fresh state
        app.launch()
        
        // Wait for app to be ready
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should be running in foreground")
        
        // Activate the app window
        app.activate()
        
        // Wait a bit more for UI to fully render
        Thread.sleep(forTimeInterval: 3.0)
        
        // Step 1: Verify the main action button is visible
        let mainActionButton = app.buttons["Run Project Analysis by Selecting a Folder..."]
        XCTAssertTrue(mainActionButton.waitForExistence(timeout: 10), "Main action button should be visible")
        
        // Step 2: Test that the button is interactive (this will open the file picker)
        mainActionButton.tap()
        
        // Note: We can't easily test the file picker in UI tests, so we just verify the button works
        // In a real scenario, this would open the file picker and allow directory selection
    }
    
    /// This test verifies that the app shows the correct title and description
    @MainActor
    func testAppTitleAndDescription() throws {
        // Launch app with fresh state
        app.launch()
        
        // Wait for app to be ready
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should be running in foreground")
        
        // Activate the app window
        app.activate()
        
        // Wait a bit more for UI to fully render
        Thread.sleep(forTimeInterval: 3.0)
        
        // Step 1: Verify the main title is visible
        let titleText = app.staticTexts["Swift Project Linter"]
        XCTAssertTrue(titleText.waitForExistence(timeout: 10), "Main title should be visible")
        
        // Step 2: Verify the description text is visible
        let descriptionText = app.staticTexts["Detect cross-file issues and architectural problems"]
        XCTAssertTrue(descriptionText.waitForExistence(timeout: 10), "Description text should be visible")
    }
    
    func testMainActionButtonTriggersAnalysis() {
        // Given
        app.launch()
        
        // Wait for app to be ready
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should be running in foreground")
        
        // Activate the app window
        app.activate()
        
        // Wait a bit more for UI to fully render
        Thread.sleep(forTimeInterval: 3.0)
        
        // Wait for the main action button to be available
        let mainActionButton = app.buttons["Run Project Analysis by Selecting a Folder..."]
        XCTAssertTrue(mainActionButton.waitForExistence(timeout: 10.0))
        
        // When - Tap the main action button to trigger folder selection
        mainActionButton.tap()
        
        // Note: In UI tests, we can't actually select a folder through the file picker
        // But we can verify that the button tap doesn't crash the app
        // and that the app remains responsive
        
        // Then - Wait a moment for any potential analysis to start
        Thread.sleep(forTimeInterval: 2.0)
        
        // Verify the main action button is still accessible (app didn't crash)
        XCTAssertTrue(mainActionButton.exists)
        
        print("DEBUG: testMainActionButtonTriggersAnalysis completed successfully")
    }
    
    // MARK: - Merged tests from RobustSwiftProjectLintUITests
    
    /// Test that the app process is running and ready
    func testAppProcessIsRunning() {
        // Ensure app is launched
        app.launch()
        
        let running = app.wait(for: .runningForeground, timeout: 10)
        XCTAssertTrue(running, "App should be running in foreground")
    }
    
    /// Test main window title and buttons presence and interactivity
    func testMainWindowAndButtons() {
        app.launch()
        
        // Wait for main window to be ready
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should be running in foreground")
        app.activate()
        
        Thread.sleep(forTimeInterval: 2.0)
        
        // Check main window title
        let title = app.staticTexts["Swift Project Linter"]
        XCTAssertTrue(title.exists, "Main window title should exist")
        
        // Check buttons exist and are hittable
        let selectRulesButton = app.buttons["Select Rules"]
        XCTAssertTrue(selectRulesButton.exists, "Select Rules button should exist")
        XCTAssertTrue(selectRulesButton.isHittable, "Select Rules button should be hittable")
        
        let mainActionButton = app.buttons["Run Project Analysis by Selecting a Folder..."]
        XCTAssertTrue(mainActionButton.exists, "Main action button should exist")
        XCTAssertTrue(mainActionButton.isHittable, "Main action button should be hittable")
        
        // Test tapping Select Rules opens and cancels the sheet
        selectRulesButton.tap()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Rule selection sheet should appear")
        
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "Cancel button should appear")
        cancelButton.tap()
        
        XCTAssertFalse(sheet.waitForExistence(timeout: 5), "Rule selection sheet should dismiss after cancel")
    }
    
    /// Logs the accessibility hierarchy for debugging purposes
    func testLogAccessibilityHierarchy() {
        app.launch()
        
        // Wait for app to be ready
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should be running in foreground")
        
        // Log the entire accessibility hierarchy for inspection
        let hierarchy = app.debugDescription
        print("Accessibility Hierarchy:\n\(hierarchy)")
        
        // This test is mainly for debugging and does not assert
    }
    
    // MARK: - Helper Methods
    
    private func createTestDirectory() -> String {
        // Create a unique temporary directory with sample Swift files for testing
        let uniqueID = UUID().uuidString
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftProjectLintTest-\(uniqueID)")
        
        do {
            // Create directory
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // Track the directory for cleanup
            testDirectories.append(tempDir.path)
            
            // Create sample Swift files with various issues
            let stateManagementFile = tempDir.appendingPathComponent("StateManagementView.swift")
            let stateManagementContent = """
            struct StateManagementView: View {
                @State private var isLoading: Bool
                @State private var counter = 0
                
                var body: some View {
                    VStack {
                        Text("Count: \\(counter)")
                        Button("Increment") {
                            counter += 1
                        }
                    }
                }
            }
            """
            try stateManagementContent.write(to: stateManagementFile, atomically: true, encoding: .utf8)
            
            let performanceFile = tempDir.appendingPathComponent("PerformanceView.swift")
            let performanceContent = """
            struct PerformanceView: View {
                let items = Array(0..<1000)
                
                var body: some View {
                    ForEach(items, id: \\.self) { item in
                        Text("Item \\(item)")
                            .padding()
                            .background(Color.blue)
                    }
                }
            }
            """
            try performanceContent.write(to: performanceFile, atomically: true, encoding: .utf8)
            
            let architectureFile = tempDir.appendingPathComponent("ArchitectureView.swift")
            let architectureContent = """
            struct ArchitectureView: View {
                @State private var data: [String] = []
                @State private var isLoading = false
                @State private var error: String?
                @State private var selectedItem: String?
                @State private var showDetail = false
                @State private var searchText = ""
                @State private var sortOrder = SortOrder.ascending
                @State private var filterEnabled = false
                @State private var refreshTrigger = false
                @State private var animationEnabled = true
                
                var body: some View {
                    VStack {
                        Text("Complex View")
                    }
                }
            }
            """
            try architectureContent.write(to: architectureFile, atomically: true, encoding: .utf8)
            
        } catch {
            XCTFail("Failed to create test directory: \(error)")
        }
        
        return tempDir.path
    }
}
