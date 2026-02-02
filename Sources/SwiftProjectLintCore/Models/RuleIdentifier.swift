//
//  RuleIdentifier.swift
//  SwiftProjectLint
//
//  Created by joe cursio on 7/14/25.
//
import Foundation
import SwiftParser
import SwiftSyntax

/// Enum representing all available lint rules in the system.
/// This provides type-safe rule identification and eliminates string matching issues.
public enum RuleIdentifier: String, CaseIterable, Codable, Sendable {
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
    case deprecatedAnimation = "Deprecated Animation"

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
    case unknown = "Unknown"

    /// Returns the category this rule belongs to
    var category: PatternCategory {
        switch self {
        // State Management Rules
        case .relatedDuplicateStateVariable, .unrelatedDuplicateStateVariable,
             .uninitializedStateVariable, .missingStateObject, .unusedStateVariable, .fatView:
            return .stateManagement

            // Performance Rules
        case .expensiveOperationInViewBody, .forEachWithoutID, .largeViewBody, .forEachSelfID, .unnecessaryViewUpdate:
            return .performance

        case .deprecatedAnimation:
            return .animation

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
        case .nestedNavigationView, .missingPreview, .forEachWithSelfID,
             .forEachWithoutIDUI, .inconsistentStyling, .basicErrorHandling:
            return .uiPatterns

            // Other/System Rules
        case .fileParsingError, .unknown:
            return .other
        }
    }

    /// Returns the display name for the rule
    var displayName: String {
        return rawValue
    }
}
