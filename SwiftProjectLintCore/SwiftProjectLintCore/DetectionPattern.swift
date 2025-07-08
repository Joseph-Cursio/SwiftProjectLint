import Foundation

// MARK: - Rule Identifier

/// Enum representing all available lint rules in the system.
/// This provides type-safe rule identification and eliminates string matching issues.
public enum RuleIdentifier: String, CaseIterable {
    // State Management Rules
    case relatedDuplicateStateVariable = "Related Duplicate State Variable"
    case unrelatedDuplicateStateVariable = "Unrelated Duplicate State Variable"
    case missingStateObject = "Missing StateObject"
    case uninitializedState = "Uninitialized State"
    case unusedStateVariable = "Unused State Variable"
    case fatView = "Fat View"
    
    // Performance Rules
    case expensiveOperationsInBody = "Expensive Operations in Body"
    case forEachWithoutID = "ForEach Without ID"
    case largeViewBody = "Large View Body"
    case forEachSelfAsID = "ForEach .self as ID"
    case unnecessaryViewUpdate = "Unnecessary View Update"
    
    // Architecture Rules
    case fatViewDetection = "Fat View Detection"
    case missingDependencyInjection = "Missing Dependency Injection"
    
    // Code Quality Rules
    case magicNumbers = "Magic Numbers"
    case hardcodedStrings = "Hardcoded Strings"
    case longFunctions = "Long Functions"
    case missingDocumentation = "Missing Documentation"
    
    // Security Rules
    case hardcodedSecret = "Hardcoded Secret"
    case unsafeURL = "Unsafe URL"
    
    // Accessibility Rules
    case imageMissingAccessibility = "Image Missing Accessibility"
    case buttonMissingAccessibility = "Button Missing Accessibility"
    case inaccessibleColorUsage = "Inaccessible Color Usage"
    
    // Memory Management Rules
    case potentialRetainCycle = "Potential Retain Cycle"
    case largeObjectInState = "Large Object in State"
    
    // Networking Rules
    case missingErrorHandling = "Missing Error Handling"
    case synchronousNetworking = "Synchronous Networking"
    
    // UI Pattern Rules
    case nestedNavigation = "Nested Navigation"
    case missingPreview = "Missing Preview"
    case inconsistentStyling = "Inconsistent Styling"
    case forEachWithoutID_UI = "ForEach Without ID (UI)"
    case basicErrorHandling = "Basic Error Handling"
    
    /// Returns the display name for the rule
    var displayName: String {
        return rawValue
    }
    
    /// Returns the category this rule belongs to
    var category: PatternCategory {
        switch self {
        case .relatedDuplicateStateVariable, .unrelatedDuplicateStateVariable, .missingStateObject, .uninitializedState, .unusedStateVariable, .fatView:
            return .stateManagement
        case .expensiveOperationsInBody, .forEachWithoutID, .largeViewBody, .forEachSelfAsID, .unnecessaryViewUpdate:
            return .performance
        case .fatViewDetection, .missingDependencyInjection:
            return .architecture
        case .magicNumbers, .hardcodedStrings, .longFunctions, .missingDocumentation:
            return .codeQuality
        case .hardcodedSecret, .unsafeURL:
            return .security
        case .imageMissingAccessibility, .buttonMissingAccessibility, .inaccessibleColorUsage:
            return .accessibility
        case .potentialRetainCycle, .largeObjectInState:
            return .memoryManagement
        case .missingErrorHandling, .synchronousNetworking:
            return .networking
        case .nestedNavigation, .missingPreview, .inconsistentStyling, .forEachWithoutID_UI, .basicErrorHandling:
            return .uiPatterns
        }
    }
}

// MARK: - Pattern Category

/// Represents logical categories of code patterns that can be detected within Swift source files.
/// Each category groups related patterns corresponding to common concerns in SwiftUI development,
/// architecture, or best practices:
///
/// - `stateManagement`: Patterns related to property wrappers, state handling, and the management of stateful data within views.
/// - `performance`: Patterns that may negatively affect performance, such as inefficient collection usage or large view bodies.
/// - `architecture`: Patterns connected to software architecture, such as MVVM adherence, dependency injection, and modular design.
/// - `codeQuality`: Patterns affecting maintainability, readability, and clarity, including magic numbers, documentation, and code style.
/// - `security`: Patterns that pose potential security risks, such as hardcoded secrets or unsafe URL handling.
/// - `accessibility`: Patterns highlighting accessibility concerns, such as missing labels or hints for UI components.
/// - `memoryManagement`: Patterns indicating possible memory issues, such as retain cycles or inefficient state storage.
/// - `networking`: Patterns related to network operations, error handling, and asynchronous calls.
/// - `uiPatterns`: Patterns concerning user interface structure and design conventions, such as navigation usage, previews, or styling consistency.
public enum PatternCategory: CaseIterable {
    case stateManagement
    case performance
    case architecture
    case codeQuality
    case security
    case accessibility
    case memoryManagement
    case networking
    case uiPatterns
}

// MARK: - Detection Pattern (UI Compatibility)

/// Represents a code pattern to detect within Swift source files, used for UI compatibility.
/// This struct provides a bridge between the SwiftSyntax-based pattern system and the UI layer.
/// Each detection pattern is associated with a category, severity level, user-facing message, and suggestion.
///
/// Detection patterns are used by the UI to display available patterns and their configuration.
/// The actual detection is performed by SwiftSyntax-based visitors, not regex patterns.
///
/// - Parameters:
///   - name: The display name of the pattern (used for reporting).
///   - regex: Not used in SwiftSyntax-based detection (kept for compatibility).
///   - severity: The level of importance of the detected issue (e.g., info, warning, error).
///   - message: A user-facing message template.
///   - suggestion: A recommended action or fix to resolve the detected issue.
///   - category: The logical category of the pattern (such as code quality, performance, or security).
public struct DetectionPattern {
    public let name: String
    public let regex: String // Not used in SwiftSyntax-based detection
    public let severity: IssueSeverity
    public let message: String
    public let suggestion: String
    public let category: PatternCategory
    
    public init(name: String, regex: String, severity: IssueSeverity, message: String, suggestion: String, category: PatternCategory) {
        self.name = name
        self.regex = regex
        self.severity = severity
        self.message = message
        self.suggestion = suggestion
        self.category = category
    }
} 
