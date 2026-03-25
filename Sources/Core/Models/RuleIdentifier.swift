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
    case magicLayoutNumber = "Magic Layout Number"
    case hardcodedStrings = "Hardcoded Strings"
    case missingDocumentation = "Missing Documentation"
    case protocolNamingSuffix = "Protocol Naming Suffix"
    case actorNamingSuffix = "Actor Naming Suffix"
    case actorAgentName = "Actor Agent Name"
    case nonActorAgentSuffix = "Non-Actor Agent Suffix"
    case propertyWrapperNamingSuffix = "Property Wrapper Naming Suffix"
    case macroNegation = "Macro Negation"
    case testMissingRequire = "Test Missing Require"
    case testMissingAssertion = "Test Missing Assertion"
    case lowercasedContains = "Lowercased Contains"
    case multipleTypesPerFile = "Multiple Types Per File"
    case actorReentrancy = "Actor Reentrancy"
    case forceTry = "Force Try"
    case forceUnwrap = "Force Unwrap"
    case printStatement = "Print Statement"
    case emptyCatch = "Empty Catch"
    case todoComment = "TODO Comment"
    case taskDetached = "Task Detached"
    case asyncLetUnused = "Async Let Unused"
    case buttonClosureWrapping = "Button Closure Wrapping"
    case nonisolatedUnsafe = "Nonisolated Unsafe"
    case taskYieldOffload = "Task Yield Offload"
    case swallowedTaskError = "Swallowed Task Error"
    case couldBePrivate = "Could Be Private"
    case publicInAppTarget = "Public in App Target"
    case couldBePrivateMember = "Could Be Private Member"
    case protocolCouldBePrivate = "Protocol Could Be Private"

    // Modernization Rules
    case dateNow = "Date Now"
    case dispatchMainAsync = "Dispatch Main Async"
    case threadSleep = "Thread Sleep"
    case legacyRandom = "Legacy Random"
    case cfAbsoluteTime = "CF Absolute Time"
    case legacyNotificationObserver = "Legacy Notification Observer"
    case completionHandlerDataTask = "Completion Handler Data Task"
    case taskInOnAppear = "Task in onAppear"
    case dispatchSemaphoreInAsync = "Dispatch Semaphore in Async"
    case navigationViewDeprecated = "NavigationView Deprecated"
    case observedObjectInline = "ObservedObject Inline"
    case onChangeOldAPI = "onChange Old API"
    case legacyObservableObject = "Legacy ObservableObject"

    // Security Rules
    case hardcodedSecret = "Hardcoded Secret"
    case unsafeURL = "Unsafe URL"

    // Accessibility Rules
    case missingAccessibilityLabel = "Missing Accessibility Label"
    case missingAccessibilityHint = "Missing Accessibility Hint"
    case inaccessibleColorUsage = "Inaccessible Color Usage"
    case iconOnlyButtonMissingLabel = "Icon-Only Button Missing Label"
    case longTextAccessibility = "Long Text Accessibility"
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

    /// Returns the kebab-case key used in inline suppression comments.
    ///
    /// Example: `.forceTry` → `"force-try"` → `// swiftprojectlint:disable force-try`
    public var suppressionKey: String {
        rawValue
            .components(separatedBy: .whitespaces)
            .map { $0.lowercased() }
            .joined(separator: "-")
    }

    /// Returns the category this rule belongs to
    public var category: PatternCategory {
        switch self {
        // State Management Rules
        case .relatedDuplicateStateVariable, .unrelatedDuplicateStateVariable,
             .uninitializedStateVariable, .missingStateObject, .unusedStateVariable, .fatView,
             .observedObjectInline:
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
        case .magicNumber, .magicLayoutNumber, .hardcodedStrings, .missingDocumentation,
             .protocolNamingSuffix, .actorNamingSuffix, .actorAgentName, .nonActorAgentSuffix, .propertyWrapperNamingSuffix,
             .macroNegation, .testMissingRequire, .testMissingAssertion, .lowercasedContains, .multipleTypesPerFile, .actorReentrancy,
             .forceTry, .forceUnwrap, .printStatement, .emptyCatch, .todoComment,
             .taskDetached, .asyncLetUnused, .buttonClosureWrapping,
             .nonisolatedUnsafe, .taskYieldOffload, .swallowedTaskError,
             .couldBePrivate, .publicInAppTarget, .couldBePrivateMember,
             .protocolCouldBePrivate:
            return .codeQuality

            // Security Rules
        case .hardcodedSecret, .unsafeURL:
            return .security

            // Accessibility Rules
        case .missingAccessibilityLabel, .missingAccessibilityHint, .inaccessibleColorUsage,
             .iconOnlyButtonMissingLabel, .longTextAccessibility, .hardcodedFontSize:
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

            // Modernization Rules
        case .dateNow, .dispatchMainAsync, .threadSleep, .legacyRandom, .cfAbsoluteTime,
             .legacyNotificationObserver, .completionHandlerDataTask, .taskInOnAppear,
             .dispatchSemaphoreInAsync, .navigationViewDeprecated, .onChangeOldAPI,
             .legacyObservableObject:
            return .modernization

            // Other/System Rules
        case .fileParsingError, .unknown:
            return .other
        }
    }

}
