//
//  RuleIdentifier.swift
//  SwiftProjectLint
//
//  Created by joe cursio on 7/14/25.
//
import Foundation

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
    case tooManyEnvironmentObjects = "Too Many Environment Objects"

    // Performance Rules
    case anyViewUsage = "AnyView Usage"
    case expensiveOperationInViewBody = "Expensive Operation in View Body"
    case forEachWithoutID = "ForEach Without ID"
    case largeViewBody = "Large View Body"
    case largeViewHelper = "Large View Helper"
    case forEachSelfID = "ForEach Self ID"
    case unnecessaryViewUpdate = "Unnecessary View Update"
    case viewBuilderComplexity = "ViewBuilder Complexity"
    case customModifierPerformance = "Custom Modifier Performance"
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
    case fatProtocol = "Fat Protocol"
    case singleImplementationProtocol = "Single Implementation Protocol"
    case mirrorProtocol = "Mirror Protocol"
    case computedPropertyView = "Computed Property View"
    case swiftDataUniqueAttributeCloudKit = "SwiftData Unique Attribute CloudKit"

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
    case testMissingExpect = "Test Missing Expect"
    case lowercasedContains = "Lowercased Contains"
    case multipleTypesPerFile = "Multiple Types Per File"
    case actorReentrancy = "Actor Reentrancy"
    case forceTry = "Force Try"
    case forceUnwrap = "Force Unwrap"
    case printStatement = "Print Statement"
    case emptyCatch = "Empty Catch"
    case todoComment = "TODO Comment"
    case swiftlintSuppression = "SwiftLint Suppression"
    case swiftprojectlintSuppression = "SwiftProjectLint Suppression"
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
    case variableShadowing = "Variable Shadowing"
    case uncheckedSendable = "Unchecked Sendable"
    case stringSwitchOverEnum = "String Switch Over Enum"
    case fontWeightBold = "Font Weight Bold"
    case globalActorMismatch = "Global Actor Mismatch"
    case formatterInViewBody = "Formatter In View Body"
    case geometryReaderOveruse = "GeometryReader Overuse"
    case unboundedTaskGroup = "Unbounded Task Group"
    case onReceiveWithoutDebounce = "onReceive Without Debounce"
    case mainActorMissingOnUICode = "Main Actor Missing On UI Code"
    case observableMainActorMissing = "Observable Main Actor Missing"

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
    case taskSleepNanoseconds = "Task Sleep Nanoseconds"
    case foregroundColorDeprecated = "Foreground Color Deprecated"
    case cornerRadiusDeprecated = "Corner Radius Deprecated"
    case legacyStringFormat = "Legacy String Format"
    case scrollViewReaderDeprecated = "ScrollViewReader Deprecated"
    case legacyReplacingOccurrences = "Legacy Replacing Occurrences"
    case tabItemDeprecated = "tabItem Deprecated"
    case legacyFormatter = "Legacy Formatter"
    case legacyImageRenderer = "Legacy Image Renderer"
    case scrollViewShowsIndicators = "ScrollView showsIndicators"

    // Security Rules
    case hardcodedSecret = "Hardcoded Secret"
    case insecureTransport = "Insecure Transport"
    case unsafeURL = "Unsafe URL"
    case userDefaultsSensitiveData = "User Defaults Sensitive Data"
    case loggingSensitiveData = "Logging Sensitive Data"

    // Accessibility Rules
    case missingAccessibilityLabel = "Missing Accessibility Label"
    case missingAccessibilityHint = "Missing Accessibility Hint"
    case inaccessibleColorUsage = "Inaccessible Color Usage"
    case iconOnlyButtonMissingLabel = "Icon-Only Button Missing Label"
    case longTextAccessibility = "Long Text Accessibility"
    case hardcodedFontSize = "Hardcoded Font Size"
    case onTapGestureInsteadOfButton = "onTapGesture Instead of Button"
    case tapTargetTooSmall = "Tap Target Too Small"
    case missingDynamicTypeSupport = "Missing Dynamic Type Support"

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
    case modifierOrderIssue = "Modifier Order Issue"
    case imageWithoutResizable = "Image Without Resizable"

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
             .observedObjectInline, .tooManyEnvironmentObjects, .mainActorMissingOnUICode,
             .observableMainActorMissing:
            return .stateManagement

            // Performance Rules
        case .anyViewUsage, .expensiveOperationInViewBody, .forEachWithoutID, .largeViewBody,
             .largeViewHelper, .forEachSelfID, .unnecessaryViewUpdate, .viewBuilderComplexity,
             .customModifierPerformance, .formatterInViewBody,
             .geometryReaderOveruse, .unboundedTaskGroup,
             .onReceiveWithoutDebounce:
            return .performance

        case .deprecatedAnimation, .animationInHighFrequencyUpdate, .excessiveSpringAnimations,
             .longAnimationDuration, .withAnimationInOnAppear, .animationWithoutStateChange,
             .conflictingAnimations, .matchedGeometryEffectMisuse, .defaultAnimationCurve,
             .hardcodedAnimationValues:
            return .animation

            // Architecture Rules
        case .missingDependencyInjection, .fatViewDetection, .directInstantiation,
             .concreteTypeUsage, .accessingImplementationDetails,
             .singletonUsage, .lawOfDemeter, .fatProtocol,
             .singleImplementationProtocol, .mirrorProtocol,
             .computedPropertyView,
             .swiftDataUniqueAttributeCloudKit:
            return .architecture

            // Code Quality Rules
        case .magicNumber, .magicLayoutNumber, .hardcodedStrings, .missingDocumentation,
             .protocolNamingSuffix, .actorNamingSuffix, .actorAgentName,
             .nonActorAgentSuffix, .propertyWrapperNamingSuffix,
             .macroNegation, .testMissingRequire, .testMissingAssertion,
             .testMissingExpect, .lowercasedContains, .multipleTypesPerFile, .actorReentrancy,
             .forceTry, .forceUnwrap, .printStatement, .emptyCatch,
             .todoComment, .swiftlintSuppression, .swiftprojectlintSuppression,
             .taskDetached, .asyncLetUnused, .buttonClosureWrapping,
             .nonisolatedUnsafe, .taskYieldOffload, .swallowedTaskError,
             .couldBePrivate, .publicInAppTarget, .couldBePrivateMember,
             .protocolCouldBePrivate, .variableShadowing, .uncheckedSendable,
             .stringSwitchOverEnum, .fontWeightBold,
             .globalActorMismatch:
            return .codeQuality

            // Security Rules
        case .hardcodedSecret, .insecureTransport, .unsafeURL, .userDefaultsSensitiveData,
             .loggingSensitiveData:
            return .security

            // Accessibility Rules
        case .missingAccessibilityLabel, .missingAccessibilityHint, .inaccessibleColorUsage,
             .iconOnlyButtonMissingLabel, .longTextAccessibility, .hardcodedFontSize,
             .onTapGestureInsteadOfButton, .tapTargetTooSmall,
             .missingDynamicTypeSupport:
            return .accessibility

            // Memory Management Rules
        case .potentialRetainCycle, .largeObjectInState:
            return .memoryManagement

            // Networking Rules
        case .missingErrorHandling, .synchronousNetworkCall:
            return .networking

            // UI Pattern Rules
        case .nestedNavigationView, .missingPreview, .forEachWithSelfID,
             .forEachWithoutIDUI, .inconsistentStyling, .basicErrorHandling,
             .modifierOrderIssue, .imageWithoutResizable:
            return .uiPatterns

            // Modernization Rules
        case .dateNow, .dispatchMainAsync, .threadSleep, .legacyRandom, .cfAbsoluteTime,
             .legacyNotificationObserver, .completionHandlerDataTask, .taskInOnAppear,
             .dispatchSemaphoreInAsync, .navigationViewDeprecated, .onChangeOldAPI,
             .legacyObservableObject, .taskSleepNanoseconds, .foregroundColorDeprecated,
             .cornerRadiusDeprecated, .legacyStringFormat, .scrollViewReaderDeprecated,
             .legacyReplacingOccurrences, .tabItemDeprecated,
             .legacyFormatter, .legacyImageRenderer,
             .scrollViewShowsIndicators:
            return .modernization

            // Other/System Rules
        case .fileParsingError, .unknown:
            return .other
        }
    }

}
