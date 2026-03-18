# SwiftProjectLint Rules Reference

SwiftProjectLint is a static analysis tool for SwiftUI projects. It parses Swift source files using SwiftSyntax AST visitors to detect anti-patterns spanning state management, performance, animations, architecture, code quality, security, accessibility, memory management, networking, and UI patterns. This reference documents all 57 lint rules, organized by category.

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

## Performance

| Rule | Severity |
|------|----------|
| [Expensive Operation in View Body](expensive-operation-in-view-body.md) | Warning |
| [ForEach Without ID](for-each-without-id.md) | Warning |
| [Large View Body](large-view-body.md) | Warning |
| [ForEach Self ID](for-each-self-id.md) | Warning |
| [Unnecessary View Update](unnecessary-view-update.md) | Warning |

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
| [Concrete Type Usage](concrete-type-usage.md) | Warning |
| [Accessing Implementation Details](accessing-implementation-details.md) | Warning |
| [Singleton Usage](singleton-usage.md) | Warning |
| [Law of Demeter](law-of-demeter.md) | Warning |

## Code Quality

| Rule | Severity |
|------|----------|
| [Magic Number](magic-number.md) | Info |
| [Long Function](long-function.md) | Warning |
| [Hardcoded Strings](hardcoded-strings.md) | Info |
| [Missing Documentation](missing-documentation.md) | Info |
| [Protocol Naming Suffix](protocol-naming-suffix.md) | Info |
| [Actor Naming Suffix](actor-naming-suffix.md) | Info |
| [Property Wrapper Naming Suffix](property-wrapper-naming-suffix.md) | Info |
| [Expect Negation](expect-negation.md) | Warning |

## Security

| Rule | Severity |
|------|----------|
| [Hardcoded Secret](hardcoded-secret.md) | Error |
| [Unsafe URL](unsafe-url.md) | Warning |

## Accessibility

| Rule | Severity |
|------|----------|
| [Missing Accessibility Label](missing-accessibility-label.md) | Warning |
| [Missing Accessibility Hint](missing-accessibility-hint.md) | Info |
| [Inaccessible Color Usage](inaccessible-color-usage.md) | Info |

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

## UI Patterns

| Rule | Severity |
|------|----------|
| [Nested Navigation View](nested-navigation-view.md) | Warning |
| [Missing Preview](missing-preview.md) | Info |
| [ForEach With Self ID (UI)](for-each-with-self-id.md) | Warning |
| [ForEach Without ID (UI)](for-each-without-id-ui.md) | Warning |
| [Inconsistent Styling](inconsistent-styling.md) | Info |
| [Basic Error Handling](basic-error-handling.md) | Info |

## Other

| Rule | Severity |
|------|----------|
| [File Parsing Error](file-parsing-error.md) | Error |
| [Unknown](unknown.md) | Warning |

---

*Generated from visitor source code and test cases in SwiftProjectLint. To contribute a rule correction or new rule, see the [contributor guide](../CONTRIBUTING.md).*
