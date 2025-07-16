# Detecting Concrete Type Usage in SwiftProjectLintCore

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

## 4. Model Changes
- Add a new case to `ArchitectureIssueType`: `case concreteTypeUsage`
- Optionally, add a new `RuleIdentifier` for concrete type usage

## 5. Visitor Logic
- In the relevant visitor, traverse function parameters, property declarations, and initializers
- If the type is a concrete class, emit an `ArchitectureIssue` of type `.concreteTypeUsage`
- Example pseudocode:
  ```swift
  if let param = node as? FunctionParameterSyntax,
     param.type.isConcreteClass {
      // Emit issue
  }
  ```

## 6. Pattern Registration
- Register a new `SyntaxPattern` for concrete type usage in `ArchitecturePatternRegistrar`

## 7. Testing
- Add test cases with concrete type usage and protocol-based usage
- Ensure only the former is flagged

## 8. References
- [Swift Protocol-Oriented Programming](https://www.swiftbysundell.com/articles/protocol-oriented-programming-in-swift/)
- [SOLID Principles in Swift](https://www.avanderlee.com/swift/solid-principles/) 