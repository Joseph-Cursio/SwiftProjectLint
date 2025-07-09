import XCTest
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

final class AccessibilityVisitorTests: XCTestCase {
    
    var visitor: AccessibilityVisitor!
    
    override func setUp() {
        super.setUp()
        // Initialize the pattern registry to ensure all visitors are registered
        SwiftSyntaxPatternRegistry.shared.initialize()
        visitor = AccessibilityVisitor(viewMode: .sourceAccurate)
    }
    
    override func tearDown() {
        visitor = nil
        super.tearDown()
    }
    
    // MARK: - Button with Image Missing Label Tests
    
    func testButtonWithImageMissingLabel() {
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    // action
                } label: {
                    Image("icon")
                }
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        XCTAssertEqual(visitor.detectedIssues.count, 1)
        
        let issue = visitor.detectedIssues.first!
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertTrue(issue.message.contains("Button with image missing accessibility label"))
        XCTAssertTrue(issue.suggestion?.contains("accessibilityLabel") == true)
    }
    
    func testButtonWithImageWithAccessibilityLabel() {
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    // action
                } label: {
                    Image("icon")
                }
                .accessibilityLabel("Settings")
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        XCTAssertEqual(visitor.detectedIssues.count, 0)
    }
    
    func testButtonWithTextOnly() {
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button("Click me") {
                    // action
                }
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        XCTAssertEqual(visitor.detectedIssues.count, 0)
    }
    
    // MARK: - Button with Text Missing Hint Tests
    
    func testButtonWithTextMissingHint() {
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    // action
                } label: {
                    Text("Submit Form")
                }
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        XCTAssertEqual(visitor.detectedIssues.count, 1)
        
        let issue = visitor.detectedIssues.first!
        XCTAssertEqual(issue.severity, .info)
        XCTAssertTrue(issue.message.contains("Consider adding accessibility hint"))
        XCTAssertTrue(issue.suggestion?.contains("accessibilityHint") == true)
    }
    
    func testButtonWithTextWithAccessibilityHint() {
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    // action
                } label: {
                    Text("Submit Form")
                }
                .accessibilityHint("Submits the current form data")
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        XCTAssertEqual(visitor.detectedIssues.count, 0)
    }
    
    // MARK: - Image Missing Label Tests
    
    func testImageMissingLabel() {
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Image("profile")
                    .resizable()
                    .frame(width: 100, height: 100)
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        XCTAssertEqual(visitor.detectedIssues.count, 1)
        
        let issue = visitor.detectedIssues.first!
        XCTAssertEqual(issue.severity, .warning)
        XCTAssertTrue(issue.message.contains("Image missing accessibility label"))
        XCTAssertTrue(issue.suggestion?.contains("accessibilityLabel") == true)
    }
    
    func testImageWithAccessibilityLabel() {
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Image("profile")
                    .resizable()
                    .frame(width: 100, height: 100)
                    .accessibilityLabel("User profile picture")
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        XCTAssertEqual(visitor.detectedIssues.count, 0)
    }
    
    // MARK: - Text Accessibility Tests
    
    func testLongTextMissingAccessibility() {
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("This is a very long text that should have accessibility features for better screen reader support and user experience")
            }
        }
        """
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        DebugLogger.log("Detected issues count: \(visitor.detectedIssues.count)")
        for (index, issue) in visitor.detectedIssues.enumerated() {
            DebugLogger.log("Issue \(index): \(issue.message)")
        }
        // Then
        XCTAssertEqual(visitor.detectedIssues.count, 1)
        let issue = visitor.detectedIssues.first!
        XCTAssertEqual(issue.severity, .info)
        XCTAssertTrue(issue.message.contains("Long text content may benefit from accessibility features"))
        XCTAssertTrue(issue.suggestion?.contains("accessibilityLabel") == true)
    }
    
    func testShortTextNoAccessibilityWarning() {
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        XCTAssertEqual(visitor.detectedIssues.count, 0)
    }
    
    func testTextWithAccessibilityFeatures() {
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("This is a very long text that should have accessibility features")
                    .accessibilityLabel("Important information")
                    .accessibilityHint("Contains important details about the current state")
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        XCTAssertEqual(visitor.detectedIssues.count, 0)
    }
    
    // MARK: - Color Accessibility Tests
    
    func testInaccessibleColorUsage() {
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("Status")
                    .foregroundColor(.red)
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        XCTAssertEqual(visitor.detectedIssues.count, 1)
        
        let issue = visitor.detectedIssues.first!
        XCTAssertEqual(issue.severity, .info)
        XCTAssertTrue(issue.message.contains("Consider accessibility when using color-based information"))
        XCTAssertTrue(issue.suggestion?.contains("color is not the only way") == true)
    }
    
    func testMultipleColorUsage() {
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                VStack {
                    Text("Success")
                        .foregroundColor(.green)
                    Text("Warning")
                        .foregroundColor(.yellow)
                    Text("Error")
                        .foregroundColor(.red)
                }
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        XCTAssertEqual(visitor.detectedIssues.count, 3)
        
        let colorIssues = visitor.detectedIssues.filter { $0.message.contains("color-based information") }
        XCTAssertEqual(colorIssues.count, 3)
    }
    
    // MARK: - Complex View Tests
    
    func testComplexViewWithMultipleAccessibilityIssues() {
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                VStack {
                    Button {
                        // action
                    } label: {
                        Image("settings")
                    }
                    
                    Button {
                        // action
                    } label: {
                        Text("Submit a very long form with many fields and complex validation")
                    }
                    
                    Image("logo")
                        .resizable()
                        .frame(width: 200, height: 100)
                    
                    Text("Status: Active")
                        .foregroundColor(.green)
                }
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        DebugLogger.log("Detected issues count: \(visitor.detectedIssues.count)")
        for (index, issue) in visitor.detectedIssues.enumerated() {
            DebugLogger.log("Issue \(index): \(issue.message)")
        }
        // Then
        XCTAssertEqual(visitor.detectedIssues.count, 5)
        
        let buttonWithImageIssues = visitor.detectedIssues.filter { $0.message.contains("Button with image missing accessibility label") }
        XCTAssertEqual(buttonWithImageIssues.count, 1)
        
        let buttonWithTextIssues = visitor.detectedIssues.filter { $0.message.contains("Consider adding accessibility hint") }
        XCTAssertEqual(buttonWithTextIssues.count, 1)
        
        let imageIssues = visitor.detectedIssues.filter { $0.message.contains("Image missing accessibility label") }
        XCTAssertEqual(imageIssues.count, 1)
        
        let textIssues = visitor.detectedIssues.filter { $0.message.contains("Long text content may benefit") }
        XCTAssertEqual(textIssues.count, 1)
        
        let colorIssues = visitor.detectedIssues.filter { $0.message.contains("color-based information") }
        XCTAssertEqual(colorIssues.count, 1)
    }
    
    // MARK: - Configuration Tests
    
    func testStrictConfiguration() {
        // Given
        let strictVisitor = AccessibilityVisitor(config: AccessibilityVisitor.Configuration(minTextLengthForHint: 5))
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("Short text")
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        strictVisitor.walk(sourceFile)
        DebugLogger.log("Detected issues count: \(strictVisitor.detectedIssues.count)")
        for (index, issue) in strictVisitor.detectedIssues.enumerated() {
            DebugLogger.log("Issue \(index): \(issue.message)")
        }
        // Then
        XCTAssertEqual(strictVisitor.detectedIssues.count, 1)
        
        let issue = strictVisitor.detectedIssues.first!
        XCTAssertTrue(issue.message.contains("Long text content may benefit"))
    }
    
    func testCustomConfiguration() {
        // Given
        let customConfig = AccessibilityVisitor.Configuration(minTextLengthForHint: 20)
        let customVisitor = AccessibilityVisitor(config: customConfig)
        
        // Reset to ensure clean state
        customVisitor.reset()
        
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("This is a medium length text")
            }
        }
        """
        let testText = "This is a medium length text"
        DebugLogger.log("Test text length: \(testText.count) characters")
        DebugLogger.log("Custom config minTextLengthForHint: \(customConfig.minTextLengthForHint)")
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        DebugLogger.log("Detected issues count: \(customVisitor.detectedIssues.count)")
        for (index, issue) in customVisitor.detectedIssues.enumerated() {
            DebugLogger.log("Issue \(index): \(issue.message)")
        }
        // Then
        XCTAssertEqual(customVisitor.detectedIssues.count, 1)
        
        let issue = customVisitor.detectedIssues.first!
        XCTAssertTrue(issue.message.contains("Long text content may benefit from accessibility features"))
    }
    
    func testCustomConfigurationWithLongerText() {
        // Given
        let customConfig = AccessibilityVisitor.Configuration(minTextLengthForHint: 20)
        let customVisitor = AccessibilityVisitor(config: customConfig)
        
        // Reset to ensure clean state
        customVisitor.reset()
        
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("This is a very long text that should definitely be detected as long text content")
            }
        }
        """
        
        let testText = "This is a very long text that should definitely be detected as long text content"
        DebugLogger.log("Longer text test - text length: \(testText.count) characters")
        DebugLogger.log("Custom config minTextLengthForHint: \(customConfig.minTextLengthForHint)")
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        DebugLogger.log("Longer text test - detected \(customVisitor.detectedIssues.count) issues:")
        for (index, issue) in customVisitor.detectedIssues.enumerated() {
            DebugLogger.log("Issue \(index): \(issue.message)")
        }
        
        // Then
        XCTAssertEqual(customVisitor.detectedIssues.count, 1)
        
        let issue = customVisitor.detectedIssues.first!
        XCTAssertTrue(issue.message.contains("Long text content may benefit from accessibility features"))
    }
    
    func testSimpleTextDetection() {
        // Given
        let customConfig = AccessibilityVisitor.Configuration(minTextLengthForHint: 5)
        let customVisitor = AccessibilityVisitor(config: customConfig)
        
        // Reset to ensure clean state
        customVisitor.reset()
        
        let sourceCode = """
        Text("Hello World")
        """
        
        let testText = "Hello World"
        DebugLogger.log("Simple text test - text length: \(testText.count) characters")
        DebugLogger.log("Custom config minTextLengthForHint: \(customConfig.minTextLengthForHint)")
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        DebugLogger.log("Simple text test - detected \(customVisitor.detectedIssues.count) issues:")
        for (index, issue) in customVisitor.detectedIssues.enumerated() {
            DebugLogger.log("Issue \(index): \(issue.message)")
        }
        
        // Then
        XCTAssertEqual(customVisitor.detectedIssues.count, 1)
        
        let issue = customVisitor.detectedIssues.first!
        XCTAssertTrue(issue.message.contains("Long text content may benefit from accessibility features"))
    }
    
    func testSimpleTextDetectionInView() {
        // Given
        let customConfig = AccessibilityVisitor.Configuration(minTextLengthForHint: 5)
        let customVisitor = AccessibilityVisitor(config: customConfig)
        
        // Reset to ensure clean state
        customVisitor.reset()
        
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("Hello World")
            }
        }
        """
        
        let testText = "Hello World"
        DebugLogger.log("Simple text in view test - text length: \(testText.count) characters")
        DebugLogger.log("Custom config minTextLengthForHint: \(customConfig.minTextLengthForHint)")
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        DebugLogger.log("Simple text in view test - detected \(customVisitor.detectedIssues.count) issues:")
        for (index, issue) in customVisitor.detectedIssues.enumerated() {
            DebugLogger.log("Issue \(index): \(issue.message)")
        }
        
        // Then
        XCTAssertEqual(customVisitor.detectedIssues.count, 1)
        
        let issue = customVisitor.detectedIssues.first!
        XCTAssertTrue(issue.message.contains("Long text content may benefit from accessibility features"))
    }
    
    func testOriginalTextWithLowerThreshold() {
        // Given
        let customConfig = AccessibilityVisitor.Configuration(minTextLengthForHint: 10)
        let customVisitor = AccessibilityVisitor(config: customConfig)
        
        // Reset to ensure clean state
        customVisitor.reset()
        
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("This is a medium length text")
            }
        }
        """
        
        let testText = "This is a medium length text"
        DebugLogger.log("Original text with lower threshold test - text length: \(testText.count) characters")
        DebugLogger.log("Custom config minTextLengthForHint: \(customConfig.minTextLengthForHint)")
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        DebugLogger.log("Original text with lower threshold test - detected \(customVisitor.detectedIssues.count) issues:")
        for (index, issue) in customVisitor.detectedIssues.enumerated() {
            DebugLogger.log("Issue \(index): \(issue.message)")
        }
        
        // Then
        XCTAssertEqual(customVisitor.detectedIssues.count, 1)
        
        let issue = customVisitor.detectedIssues.first!
        XCTAssertTrue(issue.message.contains("Long text content may benefit from accessibility features"))
    }
    
    func testDifferentTextWithSameLength() {
        // Given
        let customConfig = AccessibilityVisitor.Configuration(minTextLengthForHint: 10)
        let customVisitor = AccessibilityVisitor(config: customConfig)
        
        // Reset to ensure clean state
        customVisitor.reset()
        
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
            }
        }
        """
        
        let testText = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        DebugLogger.log("Different text with same length test - text length: \(testText.count) characters")
        DebugLogger.log("Custom config minTextLengthForHint: \(customConfig.minTextLengthForHint)")
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        DebugLogger.log("Different text with same length test - detected \(customVisitor.detectedIssues.count) issues:")
        for (index, issue) in customVisitor.detectedIssues.enumerated() {
            DebugLogger.log("Issue \(index): \(issue.message)")
        }
        
        // Then
        XCTAssertEqual(customVisitor.detectedIssues.count, 1)
        
        let issue = customVisitor.detectedIssues.first!
        XCTAssertTrue(issue.message.contains("Long text content may benefit from accessibility features"))
    }
    
    func testTextWithoutModifier() {
        // Given
        let customConfig = AccessibilityVisitor.Configuration(minTextLengthForHint: 10)
        let customVisitor = AccessibilityVisitor(config: customConfig)
        
        // Reset to ensure clean state
        customVisitor.reset()
        
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
            }
        }
        """
        
        let testText = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        DebugLogger.log("Text without modifier test - text length: \(testText.count) characters")
        DebugLogger.log("Custom config minTextLengthForHint: \(customConfig.minTextLengthForHint)")
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        customVisitor.walk(sourceFile)
        DebugLogger.log("Text without modifier test - detected \(customVisitor.detectedIssues.count) issues:")
        for (index, issue) in customVisitor.detectedIssues.enumerated() {
            DebugLogger.log("Issue \(index): \(issue.message)")
        }
        
        // Then
        XCTAssertEqual(customVisitor.detectedIssues.count, 1)
        
        let issue = customVisitor.detectedIssues.first!
        XCTAssertTrue(issue.message.contains("Long text content may benefit from accessibility features"))
    }
    
    // MARK: - Edge Cases
    
    func testEmptyView() {
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                EmptyView()
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        XCTAssertEqual(visitor.detectedIssues.count, 0)
    }
    
    func testViewWithNoAccessibilityIssues() {
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                VStack {
                    Button("Click me") {
                        // action
                    }
                    .accessibilityHint("Performs the main action")
                    
                    Image("icon")
                        .accessibilityLabel("Application icon")
                    
                    Text("Short text")
                }
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        
        // Then
        XCTAssertEqual(visitor.detectedIssues.count, 0)
    }
    
    // MARK: - Debug Tests
    
    func testDebugButtonAST() {
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    // action
                } label: {
                    Text("Submit Form")
                }
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        
        // Print the AST structure to understand the Button syntax
        print("DEBUG: AST structure:")
        print(sourceFile.description)
        
        // Then - just verify we can parse it
        XCTAssertTrue(true)
    }
    
    func testVisitorIsCalled() {
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        print("DEBUG: About to walk source file")
        visitor.walk(sourceFile)
        print("DEBUG: Finished walking source file")
        print("DEBUG: Detected issues count: \(visitor.detectedIssues.count)")
        
        // Then - just verify the visitor was called
        XCTAssertTrue(true)
    }
    
    func testVisitorVisitMethod() {
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    // action
                } label: {
                    Text("Submit Form")
                }
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        print("DEBUG: About to walk source file")
        
        // Create a simple visitor and test if visit is called
        let testVisitor = AccessibilityVisitor(viewMode: .sourceAccurate)
        testVisitor.walk(sourceFile)
        
        print("DEBUG: Finished walking source file")
        print("DEBUG: Detected issues count: \(testVisitor.detectedIssues.count)")
        
        // Then - just verify the visitor was called
        XCTAssertTrue(true)
    }
    
    func testDebugButtonTextDetection() {
        // Given
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Button {
                    // action
                } label: {
                    Text("Submit Form")
                }
            }
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        print("DEBUG: About to walk source file")
        visitor.walk(sourceFile)
        print("DEBUG: Finished walking source file")
        print("DEBUG: Detected issues count: \(visitor.detectedIssues.count)")
        
        // Then - just verify the visitor was called and check what it detected
        XCTAssertTrue(true)
    }
    
    func testDirectContainsTextMethod() {
        // Given
        let sourceCode = """
        Button {
            Text("Submit")
        }
        """
        
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        
        // Create a visitor and test the containsText method directly
        let testVisitor = AccessibilityVisitor(viewMode: .sourceAccurate)
        
        // Find the Button node and test containsText
        var foundButton = false
        var containsTextResult = false
        
        for child in sourceFile.children(viewMode: .sourceAccurate) {
            if let functionCall = child.as(FunctionCallExprSyntax.self),
               let calledExpression = functionCall.calledExpression.as(DeclReferenceExprSyntax.self),
               calledExpression.baseName.text == "Button" {
                foundButton = true
                containsTextResult = testVisitor.containsText(functionCall)
                break
            }
        }
        
        print("DEBUG: Found Button: \(foundButton)")
        print("DEBUG: Contains Text: \(containsTextResult)")
        
        // Then - just verify we can test the method
        XCTAssertTrue(true)
    }
    
    func testTextWithAccessibilityAndUnrelatedModifiers() {
        DebugLogger.log("Test starting")
        // Given
        let customConfig = AccessibilityVisitor.Configuration(minTextLengthForHint: 10)
        let customVisitor = AccessibilityVisitor(config: customConfig)
        customVisitor.reset()
        let sourceCode = """
        struct ContentView: View {
            var body: some View {
                Text("This is a long text for accessibility testing.")
                    .foregroundColor(.blue)
                    .accessibilityLabel("Summary")
            }
        }
        """
        DebugLogger.log("About to parse source code")
        // When
        let sourceFile = Parser.parse(source: sourceCode)
        DebugLogger.log("Successfully parsed source code")
        
        // Write the AST structure to a file for debugging in the debug subdirectory
        let astDescription = sourceFile.description
        DebugLogger.logAST(astDescription)
        
        let debugDirectory = DebugLogger.debugDirectory()
        let astFilePath = URL(fileURLWithPath: debugDirectory).appendingPathComponent("debug_ast.txt")
        
        do {
            try astDescription.write(to: astFilePath, atomically: true, encoding: .utf8)
            DebugLogger.log("AST written to: \(astFilePath.path)")
        } catch {
            DebugLogger.log("Failed to write AST to debug directory: \(error)")
        }
        DebugLogger.log("Finished AST write attempts")
        customVisitor.walk(sourceFile)
        // Debug output
        DebugLogger.log("Detected issues count: \(customVisitor.detectedIssues.count)")
        for (index, issue) in customVisitor.detectedIssues.enumerated() {
            DebugLogger.log("Issue \(index): \(issue.message)")
        }
        // Then
        // Should NOT detect an accessibility issue because .accessibilityLabel is present
        XCTAssertEqual(customVisitor.detectedIssues.count, 0)
    }
} 