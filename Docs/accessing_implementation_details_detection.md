# Detecting Accessing Implementation Details in SwiftProjectLintCore

> **Status**: Proposal / Not Yet Implemented
>
> This document outlines a planned feature for detecting when code accesses implementation details of other components. See the checklist in Section 8 for implementation progress.

## 1. Definition
Accessing implementation details refers to a component using internal or private members of another component, rather than interacting through its public interface or protocol. This breaks encapsulation and increases coupling.

## 2. Rationale
- Breaks encapsulation and abstraction
- Increases risk of bugs when implementation changes
- Makes refactoring and testing harder

## 3. Detection Heuristics
- Look for code that accesses `internal` or `private` members of another type (outside its own module or class)
- Look for use of members not declared in a protocol when accessed via a concrete type
- This may require advanced AST analysis and/or symbol resolution

## 4. Model Changes
- Add a new case to `ArchitectureIssueType`: `case accessingImplementationDetails`
- Optionally, add a new `RuleIdentifier` for this concern

## 5. Visitor Logic
- In the relevant visitor, analyze member access expressions
- If a component accesses a non-public member of another type, emit an `ArchitectureIssue` of type `.accessingImplementationDetails`
- Example pseudocode:
  ```swift
  if let memberAccess = node as? MemberAccessExprSyntax,
     memberAccess.accessedMember.isInternalOrPrivate,
     memberAccess.targetType != selfType {
      // Emit issue
  }
  ```

## 6. Pattern Registration
- Register a new `SyntaxPattern` for this concern in `ArchitecturePatternRegistrar`

## 7. Testing
- Add test cases where a component accesses another's internal/private members, and where it uses only the public interface
- Ensure only the former is flagged

## 8. Checklist for Improving Detection

- [ ] **Integrate SwiftSyntax with Symbol Resolution**
  - [ ] Investigate using SwiftSyntax and/or SourceKit-LSP for AST and symbol information.
  - [ ] Implement logic to resolve member visibility and type boundaries.

- [ ] **Enhance Protocol Conformance Awareness**
  - [ ] Update visitor logic to check if accessed members are part of a protocol interface.
  - [ ] Only flag access if the member is not part of the protocol.

- [ ] **Add Module Boundary Checks**
  - [ ] Ensure detection distinguishes between same-module and cross-module access.
  - [ ] Only flag cross-type, cross-module access to non-public members.

- [ ] **Reduce False Positives**
  - [ ] Ignore member accesses within extensions of the same type.
  - [ ] Allow test targets to access internal members if `@testable import` is used.

- [ ] **Make Rule Configurable**
  - [ ] Allow users to configure which access levels (`private`, `internal`) to flag.

- [ ] **Improve Issue Reporting**
  - [ ] Include accessed member name, declared access level, and source/target type in issue messages.

- [ ] **Expand and Refine Testing**
  - [ ] Add tests for:
    - [ ] Access via protocol-typed variables.
    - [ ] Access to `fileprivate` members.
    - [ ] Access in nested types and extensions.
    - [ ] Cross-module and same-module scenarios.

- [ ] **Update Documentation**
  - [ ] Document new detection logic and configuration options.
  - [ ] Provide examples and rationale for each improvement.

- [ ] **Refactor and Register Patterns**
  - [ ] Enhance the relevant visitor (e.g., `ArchitectureVisitor`).
  - [ ] Update `ArchitectureIssueType` and `ArchitecturePatternRegistrar` as needed.

## 9. References
- [Code Encapsulation in Swift](https://www.swiftbysundell.com/articles/code-encapsulation-in-swift/) Swift by Sundell
- [Access Control](https://www.swiftbysundell.com/basics/access-control/) Swift by Sundell
- [Swift Access Control](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/accesscontrol/) from Swift documentation