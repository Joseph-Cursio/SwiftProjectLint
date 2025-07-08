// Merged into SwiftProjectLintUITests.swift
/*
final class RobustSwiftProjectLintUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testAppProcessIsRunning() throws {
        app.launch()
        
        // Check if the app process is running
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should be running in foreground")
        
        // Try to find any UI elements, not just windows
        let allElements = app.descendants(matching: .any)
        print("Found \(allElements.count) total UI elements")
        
        // Print first 10 elements for debugging
        for i in 0..<min(10, allElements.count) {
            let element = allElements.element(boundBy: i)
            print("Element[\(i)]: \(element.debugDescription)")
        }
        
        // Even if no windows, we should have some elements
        XCTAssertTrue(allElements.count > 0, "Should find at least some UI elements")
    }

    func testMainWindowAndButtons() throws {
        app.launch()
        
        // Wait for app to be ready
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "App should be running in foreground")
        
        // Wait a bit more for UI to fully render
        Thread.sleep(forTimeInterval: 3.0)
        
        // Retry for up to 15 seconds to find at least one window
        let windows = app.windows
        var foundWindow = false
        for _ in 0..<30 {
            if windows.count > 0 {
                foundWindow = true
                break
            }
            sleep(1)
        }
        if !foundWindow {
            // Log all windows and their debug descriptions
            print("No windows found. Logging all windows:")
            for i in 0..<windows.count {
                let window = windows.element(boundBy: i)
                print("Window[\(i)]: \(window.debugDescription)")
            }
        }
        
        XCTAssertTrue(foundWindow, "At least one window should exist")
        
        // Try to find buttons using different strategies
        let buttons = app.buttons
        print("Found \(buttons.count) buttons")
        
        for i in 0..<buttons.count {
            let button = buttons.element(boundBy: i)
            print("Button[\(i)]: \(button.label) - \(button.debugDescription)")
        }
        
        // Try to find static texts
        let staticTexts = app.staticTexts
        print("Found \(staticTexts.count) static texts")
        
        for i in 0..<min(5, staticTexts.count) {
            let text = staticTexts.element(boundBy: i)
            print("StaticText[\(i)]: \(text.label) - \(text.debugDescription)")
        }
        
        // If we found any buttons, try to tap the first one
        if buttons.count > 0 {
            let firstButton = buttons.element(boundBy: 0)
            print("Attempting to tap button: \(firstButton.label)")
            firstButton.tap()
            
            // Wait a moment and check if any UI changed
            sleep(2)
            
            // Check if any sheets or alerts appeared
            let sheets = app.sheets
            let alerts = app.alerts
            print("After tap - Sheets: \(sheets.count), Alerts: \(alerts.count)")
        }
    }

    func testLogAccessibilityHierarchy() throws {
        app.launch()
        
        // Wait for app to be ready
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), "App should be running in foreground")
        
        // Log the entire accessibility hierarchy
        print("=== ACCESSIBILITY HIERARCHY ===")
        print(app.debugDescription)
        print("=== END ACCESSIBILITY HIERARCHY ===")
        
        // Also try to find the main window specifically
        let mainWindow = app.windows["SwiftProjectLint"]
        if mainWindow.exists {
            print("Found main window: \(mainWindow.debugDescription)")
        } else {
            print("Main window not found")
        }
    }
} 
*/
