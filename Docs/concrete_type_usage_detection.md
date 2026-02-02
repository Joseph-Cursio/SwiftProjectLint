# Detecting Concrete Type Usage in SwiftProjectLintCore

> **Status**: Proposal / Not Yet Implemented
>
> This document outlines a planned feature for detecting when code uses concrete types instead of protocols or abstractions.

## 1. Definition
Concrete type usage refers to declaring dependencies, properties, or parameters as specific concrete types (e.g., `let service: MyService`) instead of protocols or abstractions (e.g., `let service: ServiceProtocol`).

## 2. Rationale
- Reduces flexibility and testability
- Makes code harder to mock or substitute
- Violates dependency inversion and interface segregation principles

## 3. Detection Heuristics
- Look for function parameters, properties, or initializers where the type is a concrete class (not a protocol or generic)
- Exclude value types if desired
- Exclude basic types such as `Int`, `String`, `Bool`, `Double`, etc.
- Exclude cases where the type is a protocol or generic

### Rationale for Excluding Value Types (if desired)
- **Immutability and Simplicity:** Value types (`struct`, `enum`) are typically immutable and used for simple data or domain modeling, not for managing dependencies or shared state.
- **No Shared Mutable State:** Value types are copied on assignment, so using a concrete value type does not create hidden dependencies or side effects between components.
- **Swift Idioms and Performance:** Swift encourages value types for most data modeling due to performance and safety; flagging their usage would go against best practices and create false positives.
- **Architectural Impact:** The risks of tight coupling and difficulty in mocking are much greater with reference types (`class`). Value types rarely require protocol abstraction for architectural reasons.
- **Flexibility for Project Needs:** Some teams may want to enforce protocol usage for value types, so this exclusion is optional to allow customization.

**Summary:** Excluding value types keeps the rule focused on architectural risks from reference types, aligns with Swift best practices, and reduces noise from false positives.

---

## 4. Suggestions for Improving Detection

### 4.1 Handle Typealiases and Nested Types
- Detect when a typealias points to a concrete class (e.g., `typealias Foo = MyService`) and flag usages of `Foo`.
- Consider nested types (e.g., `Outer.InnerClass`) and ensure detection works for them.

### 4.2 Support for Generics
- Detect cases where a generic parameter is constrained to a concrete type (e.g., `T: MyService`).
- Exclude generic parameters constrained to protocols.

### 4.3 Configurable Exclusions
- Allow configuration for which value types or classes to exclude (e.g., allow `URL`, `Date`, or custom types).
- Support project-specific whitelists/blacklists.

### 4.4 Detect Implicit Usages
- Flag cases where a concrete type is used as a default value or in type inference (e.g., `let foo = MyService()`).

### 4.5 Better Protocol Detection
- Improve protocol detection by checking for the `protocol` keyword in the type declaration, not just by naming convention (e.g., not all protocols end with `Protocol`).

### 4.6 Constructor Injection
- Detect concrete type usage in initializer injection patterns, not just property or parameter declarations.

### 4.7 Reporting Improvements
- Provide more context in the lint report, such as the enclosing type and function, to make issues easier to fix.
- Suggest protocol alternatives if available.

### 4.8 SwiftUI and Combine Awareness
- Exclude or handle special cases for SwiftUI views and Combine publishers, which often use concrete types by design.

### 4.9 False Positive Reduction
- Exclude test targets or files with `@testable import` where concrete types are often used intentionally.

### 4.10 Documentation and Quick Fixes
- Link to documentation or provide quick-fix suggestions in the lint output.

---

## 5. Model Changes
- Add a new case to `ArchitectureIssueType`: `case concreteTypeUsage`
- Optionally, add a new `RuleIdentifier` for concrete type usage

---

## 6. Visitor Logic
- In the relevant visitor, traverse function parameters, property declarations, and initializers
- If the type is a concrete class, emit an `ArchitectureIssue` of type `.concreteTypeUsage`
- Example pseudocode:
  ```swift
  if let param = node as? FunctionParameterSyntax,
     param.type.isConcreteClass {
      // Emit issue
  }
  ```
- **Implementation Details:**
  - Use SwiftSyntax to traverse the AST.
  - For each `VariableDeclSyntax`, `FunctionParameterSyntax`, and `InitializerDeclSyntax`, extract the type.
  - Check if the type refers to a class (not a protocol, struct, or enum).
  - Cross-reference with a list of known protocols and value types.
  - Optionally, resolve typealiases to their underlying types.
  - Allow configuration for excluded types.

---

## 7. Pattern Registration
- Register a new `SyntaxPattern` for concrete type usage in `ArchitecturePatternRegistrar`

---

## 8. Testing
- Add test cases with concrete type usage and protocol-based usage
- Ensure only the former is flagged

---

## 9. References
- [Swift Protocol-Oriented Programming](https://www.swiftbysundell.com/articles/protocol-oriented-programming-in-swift/) Swift by Sundell
- [SOLID Principles in Swift](https://www.avanderlee.com/swift/solid-principles/) Avander Lee (hidden by paywall?)

---