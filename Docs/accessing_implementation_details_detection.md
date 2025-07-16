# Detecting Accessing Implementation Details in SwiftProjectLintCore

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

## 8. References
- [Encapsulation in Swift](https://www.swiftbysundell.com/articles/access-control-in-swift/)
- [Swift Access Control](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/accesscontrol/) 