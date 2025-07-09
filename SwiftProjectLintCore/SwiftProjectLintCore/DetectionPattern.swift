import Foundation

// MARK: - Rule Identifier

/// Enum representing all available lint rules in the system.
/// This provides type-safe rule identification and eliminates string matching issues.
public enum RuleIdentifier: String, CaseIterable, Codable {
    // State Management Rules
    case relatedDuplicateStateVariable = "Related Duplicate State Variable"
    case unrelatedDuplicateStateVariable = "Unrelated Duplicate State Variable"
    case uninitializedStateVariable = "Uninitialized State Variable"
    case missingStateObject = "Missing StateObject"
    case unusedStateVariable = "Unused State Variable"
    case fatView = "Fat View"

    // Performance Rules
    case expensiveOperationInViewBody = "Expensive Operation in View Body"
    case forEachWithoutID = "ForEach Without ID"
    case largeViewBody = "Large View Body"
    case forEachSelfID = "ForEach Self ID"
    case unnecessaryViewUpdate = "Unnecessary View Update"

    // Architecture Rules
    case missingDependencyInjection = "Missing Dependency Injection"
    case fatViewDetection = "Fat View Detection"

    // Code Quality Rules
    case magicNumber = "Magic Number"
    case longFunction = "Long Function"
    case hardcodedStrings = "Hardcoded Strings"
    case missingDocumentation = "Missing Documentation"

    // Security Rules
    case hardcodedSecret = "Hardcoded Secret"
    case unsafeURL = "Unsafe URL"

    // Accessibility Rules
    case missingAccessibilityLabel = "Missing Accessibility Label"
    case missingAccessibilityHint = "Missing Accessibility Hint"
    case inaccessibleColorUsage = "Inaccessible Color Usage"

    // Memory Management Rules
    case potentialRetainCycle = "Potential Retain Cycle"
    case largeObjectInState = "Large Object in State"

    // Networking Rules
    case missingErrorHandling = "Missing Error Handling"
    case synchronousNetworkCall = "Synchronous Network Call"

    // UI Pattern Rules
    case nestedNavigationView = "Nested Navigation View"
    case missingPreview = "Missing Preview"
    case forEachWithSelfID = "ForEach With Self ID"
    case forEachWithoutIDUI = "ForEach Without ID UI"
    case inconsistentStyling = "Inconsistent Styling"
    case basicErrorHandling = "Basic Error Handling"
    
    // Other/System Rules
    case fileParsingError = "File Parsing Error"
    
    /// Returns the category this rule belongs to
    var category: PatternCategory {
        switch self {
        // State Management Rules
        case .relatedDuplicateStateVariable, .unrelatedDuplicateStateVariable, .uninitializedStateVariable, .missingStateObject, .unusedStateVariable, .fatView:
            return .stateManagement
            
        // Performance Rules
        case .expensiveOperationInViewBody, .forEachWithoutID, .largeViewBody, .forEachSelfID, .unnecessaryViewUpdate:
            return .performance
            
        // Architecture Rules
        case .missingDependencyInjection, .fatViewDetection:
            return .architecture
            
        // Code Quality Rules
        case .magicNumber, .longFunction, .hardcodedStrings, .missingDocumentation:
            return .codeQuality
            
        // Security Rules
        case .hardcodedSecret, .unsafeURL:
            return .security
            
        // Accessibility Rules
        case .missingAccessibilityLabel, .missingAccessibilityHint, .inaccessibleColorUsage:
            return .accessibility
            
        // Memory Management Rules
        case .potentialRetainCycle, .largeObjectInState:
            return .memoryManagement
            
        // Networking Rules
        case .missingErrorHandling, .synchronousNetworkCall:
            return .networking
            
        // UI Pattern Rules
        case .nestedNavigationView, .missingPreview, .forEachWithSelfID, .forEachWithoutIDUI, .inconsistentStyling, .basicErrorHandling:
            return .uiPatterns
            
        // Other/System Rules
        case .fileParsingError:
            return .other
        }
    }
    
    /// Returns the display name for the rule
    var displayName: String {
        return rawValue
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
/// - `other`: System-level patterns and errors that don't fit into other categories, such as file parsing errors.
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
    case other
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
///   - name: The rule identifier for the pattern (used for type-safe rule identification).
///   - severity: The level of importance of the detected issue (e.g., info, warning, error).
///   - message: A user-facing message template.
///   - suggestion: A recommended action or fix to resolve the detected issue.
///   - category: The logical category of the pattern (such as code quality, performance, or security).
public struct DetectionPattern {
    public let name: RuleIdentifier
    public let severity: IssueSeverity
    public let message: String
    public let suggestion: String
    public let category: PatternCategory
    
    public init(name: RuleIdentifier, severity: IssueSeverity, message: String, suggestion: String, category: PatternCategory) {
        self.name = name
        self.severity = severity
        self.message = message
        self.suggestion = suggestion
        self.category = category
    }
} 
