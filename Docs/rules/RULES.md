# SwiftProjectLint Rules Reference

SwiftProjectLint is a static analysis tool for SwiftUI projects. It parses Swift source files using SwiftSyntax AST visitors to detect anti-patterns spanning state management, performance, animations, architecture, code quality, security, accessibility, memory management, networking, UI patterns, modernization, and idempotency. This reference documents all 160 lint rules, organized by category.

Rules marked **opt-in** are disabled by default and must be explicitly listed under `enabled_only` in `.swiftprojectlint.yml`.

---

## State Management

| Rule | Severity |
|------|----------|
| [Related Duplicate State Variable](related-duplicate-state-variable.md) | Warning |
| [Unrelated Duplicate State Variable](unrelated-duplicate-state-variable.md) | Info |
| [Uninitialized State Variable](uninitialized-state-variable.md) | Error |
| [Missing StateObject](missing-state-object.md) | Warning |
| [Unused State Variable](unused-state-variable.md) | Warning |
| [Fat View](fat-view.md) | Warning |
| [ObservedObject Inline](observed-object-inline.md) | Warning |
| [Too Many Environment Objects](too-many-environment-objects.md) | Warning |
| [Main Actor Missing On UI Code](main-actor-missing-on-ui-code.md) | Warning |
| [Observable Main Actor Missing](observable-main-actor-missing.md) | Warning |

## Performance

| Rule | Severity |
|------|----------|
| [AnyView Usage](any-view-usage.md) | Warning |
| [Expensive Operation in View Body](expensive-operation-in-view-body.md) | Warning |
| [ForEach Without ID](for-each-without-id.md) | Warning |
| [Large View Body](large-view-body.md) | Warning |
| [Large View Helper](large-view-helper.md) | Warning |
| [ForEach Self ID](for-each-self-id.md) | Warning |
| [Unnecessary View Update](unnecessary-view-update.md) | Warning |
| [ViewBuilder Complexity](view-builder-complexity.md) | Warning |
| [Custom Modifier Performance](custom-modifier-performance.md) | Warning |
| [Formatter In View Body](formatter-in-view-body.md) | Warning |
| [GeometryReader Overuse](geometry-reader-overuse.md) | Info *(opt-in)* |
| [Unbounded Task Group](unbounded-task-group.md) | Warning |
| [onReceive Without Debounce](on-receive-without-debounce.md) | Info *(opt-in)* |

## Animation

| Rule | Severity |
|------|----------|
| [Deprecated Animation](deprecated-animation.md) | Warning |
| [Animation in High Frequency Update](animation-in-high-frequency-update.md) | Warning |
| [Excessive Spring Animations](excessive-spring-animations.md) | Warning |
| [Long Animation Duration](long-animation-duration.md) | Info |
| [withAnimation in onAppear](with-animation-in-on-appear.md) | Warning |
| [Animation Without State Change](animation-without-state-change.md) | Info |
| [Conflicting Animations](conflicting-animations.md) | Warning |
| [matchedGeometryEffect Misuse](matched-geometry-effect-misuse.md) | Warning |
| [Default Animation Curve](default-animation-curve.md) | Info |
| [Hardcoded Animation Values](hardcoded-animation-values.md) | Info |

## Architecture

| Rule | Severity |
|------|----------|
| [Missing Dependency Injection](missing-dependency-injection.md) | Info |
| [Fat View Detection](fat-view-detection.md) | Warning |
| [Direct Instantiation](direct-instantiation.md) | Warning |
| [Concrete Type Usage](concrete-type-usage.md) | Info |
| [Accessing Implementation Details](accessing-implementation-details.md) | Warning |
| [Singleton Usage](singleton-usage.md) | Warning |
| [Law of Demeter](law-of-demeter.md) | Info |
| [Fat Protocol](fat-protocol.md) | Info |
| [Single Implementation Protocol](single-implementation-protocol.md) | Info |
| [Mirror Protocol](mirror-protocol.md) | Info |
| [Computed Property View](computed-property-view.md) | Warning |
| [SwiftData Unique Attribute CloudKit](swiftdata-unique-attribute-cloudkit.md) | Warning |
| [God View Model](god-view-model.md) | Warning |
| [View Model Direct DB Access](view-model-direct-db-access.md) | Info *(opt-in)* |
| [Circular Dependency](circular-dependency.md) | Warning |
| [Architectural Boundary](architectural-boundary.md) | Warning |

## Code Quality

| Rule | Severity |
|------|----------|
| [Magic Number](magic-number.md) | Info |
| [Magic Layout Number](magic-layout-number.md) | Info *(opt-in)* |
| [Hardcoded Strings](hardcoded-strings.md) | Info *(opt-in)* |
| [Missing Documentation](missing-documentation.md) | Info |
| [Protocol Naming Suffix](protocol-naming-suffix.md) | Info |
| [Actor Naming Suffix](actor-naming-suffix.md) | Info |
| [Actor Agent Name](actor-agent-name.md) | Info |
| [Non-Actor Agent Suffix](non-actor-agent-suffix.md) | Info *(opt-in)* |
| [Property Wrapper Naming Suffix](property-wrapper-naming-suffix.md) | Info |
| [Macro Negation](macro-negation.md) | Warning |
| [Test Missing Require](test-missing-require.md) | Info |
| [Test Missing Assertion](test-missing-assertion.md) | Warning |
| [Test Missing Expect](test-missing-expect.md) | Info |
| [Lowercased Contains](lowercased-contains.md) | Warning |
| [Multiple Types Per File](multiple-types-per-file.md) | Info |
| [Actor Reentrancy](actor-reentrancy.md) | Warning |
| [Force Try](force-try.md) | Warning |
| [Force Unwrap](force-unwrap.md) | Info |
| [Print Statement](print-statement.md) | Info |
| [Catch Without Handling](catch-without-handling.md) | Warning |
| [TODO Comment](todo-comment.md) | Info |
| [Task Detached](task-detached.md) | Info |
| [Async Let Unused](async-let-unused.md) | Warning |
| [Button Closure Wrapping](button-closure-wrapping.md) | Info |
| [Nonisolated Unsafe](nonisolated-unsafe.md) | Warning |
| [Task Yield Offload](task-yield-offload.md) | Info |
| [Swallowed Task Error](swallowed-task-error.md) | Warning |
| [Missing Cancellation Check](missing-cancellation-check.md) | Warning |
| [Fire And Forget Task](fire-and-forget-task.md) | Warning |
| [Discarded Try Result](discarded-try-result.md) | Warning |
| [Map Used For Side Effects](map-used-for-side-effects.md) | Warning |
| [Could Be Private](could-be-private.md) | Info |
| [Public in App Target](public-in-app-target.md) | Info |
| [Could Be Private Member](could-be-private-member.md) | Info |
| [Protocol Could Be Private](protocol-could-be-private.md) | Info |
| [Variable Shadowing](variable-shadowing.md) | Warning |
| [Unchecked Sendable](unchecked-sendable.md) | Warning |
| [Disfavored Overload](disfavored-overload.md) | Warning |
| [Retroactive Conformance](retroactive-conformance.md) | Warning |
| [Preconcurrency Conformance](preconcurrency-conformance.md) | Warning |
| [Discardable Result Misuse](discardable-result-misuse.md) | Info |
| [String Switch Over Enum](string-switch-over-enum.md) | Info *(opt-in)* |
| [SwiftLint Suppression](swiftlint-suppression.md) | Warning |
| [SwiftProjectLint Suppression](swiftprojectlint-suppression.md) | Warning |
| [Font Weight Bold](font-weight-bold.md) | Info |
| [Global Actor Mismatch](global-actor-mismatch.md) | Warning |
| [Nested Generic Complexity](nested-generic-complexity.md) | Info *(opt-in)* |
| [Magic Boolean Parameter](magic-boolean-parameter.md) | Info |

## Security

| Rule | Severity |
|------|----------|
| [Hardcoded Secret](hardcoded-secret.md) | Error |
| [Insecure Transport](insecure-transport.md) | Warning |
| [Unsafe URL](unsafe-url.md) | Warning |
| [User Defaults Sensitive Data](user-defaults-sensitive-data.md) | Error |
| [Logging Sensitive Data](logging-sensitive-data.md) | Warning |

## Accessibility

| Rule | Severity |
|------|----------|
| [Missing Accessibility Label](missing-accessibility-label.md) | Warning |
| [Missing Accessibility Hint](missing-accessibility-hint.md) | Info |
| [Inaccessible Color Usage](inaccessible-color-usage.md) | Info |
| [Icon-Only Button Missing Label](icon-only-button-missing-label.md) | Warning |
| [Long Text Accessibility](long-text-accessibility.md) | Info |
| [Hardcoded Font Size](hardcoded-font-size.md) | Warning |
| [onTapGesture Instead of Button](on-tap-gesture-instead-of-button.md) | Warning |
| [Tap Target Too Small](tap-target-too-small.md) | Warning |
| [Missing Dynamic Type Support](missing-dynamic-type-support.md) | Info *(opt-in)* |
| [Decorative Image Missing Trait](decorative-image-missing-trait.md) | Info *(opt-in)* |
| [Toggle Button Missing Selected Trait](toggle-button-missing-selected-trait.md) | Warning |
| [Button Toggling Bool](button-toggling-bool.md) | Info |
| [Stack Missing Accessibility Grouping](stack-missing-accessibility-grouping.md) | Info |
| [Accessibility Hidden Conflict](accessibility-hidden-conflict.md) | Warning |
| [Sort Priority Without Container](sort-priority-without-container.md) | Warning |

## Memory Management

| Rule | Severity |
|------|----------|
| [Potential Retain Cycle](potential-retain-cycle.md) | Warning |
| [Large Object in State](large-object-in-state.md) | Info |

## Networking

| Rule | Severity |
|------|----------|
| [Missing Error Handling](missing-error-handling.md) | Warning |
| [Synchronous Network Call](synchronous-network-call.md) | Error |
| [URLSession Unhandled Error](url-session-unhandled-error.md) | Warning |

## UI Patterns

| Rule | Severity |
|------|----------|
| [Nested Navigation View](nested-navigation-view.md) | Warning |
| [Missing Preview](missing-preview.md) | Info |
| [ForEach With Self ID](for-each-with-self-id.md) | Warning |
| [ForEach Without ID UI](for-each-without-id-ui.md) | Warning |
| [Inconsistent Styling](inconsistent-styling.md) | Info |
| [Basic Error Handling](basic-error-handling.md) | Info |
| [Modifier Order Issue](modifier-order-issue.md) | Warning |
| [Image Without Resizable](image-without-resizable.md) | Info |

## Modernization

| Rule | Severity |
|------|----------|
| [Date Now](date-now.md) | Info |
| [Dispatch Main Async](dispatch-main-async.md) | Info |
| [Thread Sleep](thread-sleep.md) | Warning |
| [Legacy Random](legacy-random.md) | Info |
| [CF Absolute Time](cf-absolute-time.md) | Info |
| [Legacy Notification Observer](legacy-notification-observer.md) | Info |
| [Completion Handler Data Task](completion-handler-data-task.md) | Info |
| [Task in onAppear](task-in-on-appear.md) | Warning |
| [Dispatch Semaphore in Async](dispatch-semaphore-in-async.md) | Warning |
| [NavigationView Deprecated](navigation-view-deprecated.md) | Warning |
| [onChange Old API](on-change-old-api.md) | Info |
| [Legacy ObservableObject](legacy-observable-object.md) | Info |
| [Task Sleep Nanoseconds](task-sleep-nanoseconds.md) | Warning |
| [Foreground Color Deprecated](foreground-color-deprecated.md) | Warning |
| [Corner Radius Deprecated](corner-radius-deprecated.md) | Warning |
| [Legacy String Format](legacy-string-format.md) | Info |
| [ScrollViewReader Deprecated](scroll-view-reader-deprecated.md) | Info |
| [Legacy Replacing Occurrences](legacy-replacing-occurrences.md) | Info |
| [tabItem Deprecated](tab-item-deprecated.md) | Info |
| [Legacy Formatter](legacy-formatter.md) | Info |
| [Legacy Image Renderer](legacy-image-renderer.md) | Info |
| [ScrollView showsIndicators](scroll-view-shows-indicators.md) | Info |
| [Legacy Array Init](legacy-array-init.md) | Info *(opt-in)* |
| [Legacy Closure Syntax](legacy-closure-syntax.md) | Info *(opt-in)* |
| [iOS 17 Observation Migration](ios17-observation-migration.md) | Info *(opt-in)* |

## Idempotency

| Rule | Severity |
|------|----------|
| [Idempotency Violation](idempotency-violation.md) | Error |
| [Non-Idempotent In Retry Context](non-idempotent-in-retry-context.md) | Error |
| [Missing Idempotency Key](missing-idempotency-key.md) | Error |
| [Once Contract Violation](once-contract-violation.md) | Error |
| [Tuple Equality With Unstable Components](tuple-equality-with-unstable-components.md) | Warning |

---

*Generated from visitor source code and test cases in SwiftProjectLint. To contribute a rule correction or new rule, see the [contributor guide](../CONTRIBUTING.md).*
