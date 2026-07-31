//
//  RuleIdentifier+Category.swift
//  SwiftProjectLint
//
//  Split out of RuleIdentifier.swift: the case list and this classification switch grow
//  together with every new rule, and together they pushed the enum body past the
//  type_body_length limit. Keeping the switch here lets both halves grow freely.
//
import Foundation

extension RuleIdentifier {

    /// Returns the category this rule belongs to
    public var category: PatternCategory {
        switch self {
        // State Management Rules
        case .relatedDuplicateStateVariable, .unrelatedDuplicateStateVariable,
             .uninitializedStateVariable, .missingStateObject, .unusedStateVariable, .fatView,
             .observedObjectInline, .tooManyEnvironmentObjects, .mainActorMissingOnUICode,
             .observableMainActorMissing, .mutuallyExclusivePresentationState,
             .flagOptionalPairState, .redundantDerivedProperty:
            return .stateManagement

            // Performance Rules
        case .anyViewUsage, .expensiveOperationInViewBody, .forEachWithoutID, .largeViewBody,
             .largeViewHelper, .forEachSelfID, .volatileViewID, .unnecessaryViewUpdate,
             .viewBuilderComplexity,
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
             .duplicateStructShape, .sharedDomainEnumField,
             .primitiveBypassingItsDomainType, .primitiveNamedForItsDomainType,
             .scatteredEnumMapping, .duplicateEnumMapping, .parallelEnumShape,
             .unusedProtocolAbstraction,
             .couldAdoptProtocol, .hoistableConformerMember,
             .hoistableSequenceOperation,
             .subclassedForMocking,
             .unabstractedFileIO,
             .computedPropertyView,
             .swiftDataUniqueAttributeCloudKit, .godViewModel,
             .viewModelDirectDBAccess, .circularDependency,
             .architecturalBoundary, .booleanControlCoupling,
             .manualRegistrationList, .parallelListDrift:
            return .architecture

            // Code Quality Rules
        case .magicNumber, .magicLayoutNumber, .hardcodedStrings, .missingDocumentation,
             .protocolNamingSuffix, .actorNamingSuffix, .actorAgentName,
             .nonActorAgentSuffix, .propertyWrapperNamingSuffix,
             .macroNegation, .testMissingRequire, .testMissingAssertion,
             .testMissingExpect, .lowercasedContains, .multipleTypesPerFile, .actorReentrancy,
             .forceTry, .forceUnwrap, .printStatement, .catchWithoutHandling,
             .todoComment, .swiftlintSuppression, .swiftprojectlintSuppression,
             .taskDetached, .asyncLetUnused, .buttonClosureWrapping,
             .nonisolatedUnsafe, .taskYieldOffload, .swallowedTaskError,
             .missingCancellationCheck, .fireAndForgetTask,
             .discardedTryResult, .lossyStructRebuild, .mapUsedForSideEffects,
             .couldBePrivate, .publicInAppTarget, .couldBePrivateMember,
             .protocolCouldBePrivate, .variableShadowing, .uncheckedSendable,
             .disfavoredOverload, .retroactiveConformance,
             .preconcurrencyConformance, .preconcurrencyImport,
             .swallowedInjectionDowncast, .discardableResultMisuse,
             .stringSwitchOverEnum, .effectCycle, .fontWeightBold,
             .globalActorMismatch, .nestedGenericComplexity,
             .magicBooleanParameter:
            return .codeQuality

            // Security Rules
        case .hardcodedSecret, .insecureTransport, .unsafeURL, .userDefaultsSensitiveData,
             .loggingSensitiveData:
            return .security

            // Accessibility Rules
        case .missingAccessibilityLabel, .missingAccessibilityHint, .inaccessibleColorUsage,
             .iconOnlyButtonMissingLabel, .longTextAccessibility, .hardcodedFontSize,
             .onTapGestureInsteadOfButton, .onTapGestureMissingAccessibility, .tapTargetTooSmall,
             .missingDynamicTypeSupport, .decorativeImageMissingTrait,
             .toggleButtonMissingSelectedTrait, .buttonTogglingBool,
             .stackMissingAccessibilityGrouping,
             .accessibilityHiddenConflict, .sortPriorityWithoutContainer,
             .controlMissingAccessibilityLabel, .isButtonTraitWithoutAction:
            return .accessibility

            // Memory Management Rules
        case .potentialRetainCycle, .largeObjectInState, .unsafeMemoryAPI:
            return .memoryManagement

            // Networking Rules
        case .missingErrorHandling, .synchronousNetworkCall, .urlSessionUnhandledError:
            return .networking

            // UI Pattern Rules
        case .nestedNavigationView, .missingPreview, .forEachWithSelfID,
             .inconsistentStyling, .basicErrorHandling,
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
             .scrollViewShowsIndicators, .legacyArrayInit,
             .legacyClosureSyntax, .ios17ObservationMigration:
            return .modernization

            // Idempotency Rules
        case .idempotencyViolation, .nonIdempotentInRetryContext, .missingIdempotencyKey,
             .onceContractViolation, .unannotatedInStrictReplayableContext,
             .tupleEqualityWithUnstableComponents, .nonIdempotentActionName:
            return .idempotency

            // Testability / PBT-readiness Rules
        case .globalMutableState, .nonInjectedNondeterminism, .pureFunctionCandidate,
             .pureClosureCandidate, .extractablePureKernel, .missingEquatableOnStateType,
             .impureCallInViewBody:
            return .testability

            // Other/System Rules
        case .fileParsingError, .unknown:
            return .other
        }
    }
}
