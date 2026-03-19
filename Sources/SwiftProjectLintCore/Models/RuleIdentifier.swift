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
    case animationInHighFrequencyUpdate = "Animation in High Frequency Update"
    case excessiveSpringAnimations = "Excessive Spring Animations"
    case longAnimationDuration = "Long Animation Duration"
    case withAnimationInOnAppear = "withAnimation in onAppear"
    case animationWithoutStateChange = "Animation Without State Change"
    case conflictingAnimations = "Conflicting Animations"
    case matchedGeometryEffectMisuse = "matchedGeometryEffect Misuse"
    case defaultAnimationCurve = "Default Animation Curve"
    case hardcodedAnimationValues = "Hardcoded Animation Values"

    // Architecture Rules
    case missingDependencyInjection = "Missing Dependency Injection"
    case fatViewDetection = "Fat View Detection"
    case directInstantiation = "Direct Instantiation"
    case concreteTypeUsage = "Concrete Type Usage"
    case accessingImplementationDetails = "Accessing Implementation Details"
    case singletonUsage = "Singleton Usage"
    case lawOfDemeter = "Law of Demeter"

    // Code Quality Rules
    case magicNumber = "Magic Number"
    case hardcodedStrings = "Hardcoded Strings"
    case missingDocumentation = "Missing Documentation"
    case protocolNamingSuffix = "Protocol Naming Suffix"
    case actorNamingSuffix = "Actor Naming Suffix"
    case propertyWrapperNamingSuffix = "Property Wrapper Naming Suffix"
    case expectNegation = "Expect Negation"
    case lowercasedContains = "Lowercased Contains"
    case multipleTypesPerFile = "Multiple Types Per File"

    // Security Rules
    case hardcodedSecret = "Hardcoded Secret"
    case unsafeURL = "Unsafe URL"

    // Accessibility Rules
    case missingAccessibilityLabel = "Missing Accessibility Label"
    case missingAccessibilityHint = "Missing Accessibility Hint"
    case inaccessibleColorUsage = "Inaccessible Color Usage"
    case iconOnlyButtonMissingLabel = "Icon-Only Button Missing Label"
    case hardcodedFontSize = "Hardcoded Font Size"

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
    public var category: PatternCategory {
        switch self {
        // State Management Rules
        case .relatedDuplicateStateVariable, .unrelatedDuplicateStateVariable,
             .uninitializedStateVariable, .missingStateObject, .unusedStateVariable, .fatView:
            return .stateManagement

            // Performance Rules
        case .expensiveOperationInViewBody, .forEachWithoutID, .largeViewBody, .forEachSelfID, .unnecessaryViewUpdate:
            return .performance

        case .deprecatedAnimation, .animationInHighFrequencyUpdate, .excessiveSpringAnimations,
             .longAnimationDuration, .withAnimationInOnAppear, .animationWithoutStateChange,
             .conflictingAnimations, .matchedGeometryEffectMisuse, .defaultAnimationCurve,
             .hardcodedAnimationValues:
            return .animation

            // Architecture Rules
        case .missingDependencyInjection, .fatViewDetection, .directInstantiation,
             .concreteTypeUsage, .accessingImplementationDetails,
             .singletonUsage, .lawOfDemeter:
            return .architecture

            // Code Quality Rules
        case .magicNumber, .hardcodedStrings, .missingDocumentation,
             .protocolNamingSuffix, .actorNamingSuffix, .propertyWrapperNamingSuffix,
             .expectNegation, .lowercasedContains, .multipleTypesPerFile:
            return .codeQuality

            // Security Rules
        case .hardcodedSecret, .unsafeURL:
            return .security

            // Accessibility Rules
        case .missingAccessibilityLabel, .missingAccessibilityHint, .inaccessibleColorUsage,
             .iconOnlyButtonMissingLabel, .hardcodedFontSize:
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

}
