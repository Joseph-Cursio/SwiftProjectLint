# Detecting Direct Instantiation in SwiftProjectLintCore

## 1. Definition
Direct instantiation refers to the practice of creating concrete instances of dependencies (e.g., `let model = MyModel()`) directly within a component, rather than injecting them. This can lead to tight coupling and reduced testability.

## 2. Rationale
- Makes components harder to test and mock
- Reduces flexibility and increases maintenance cost
- Violates dependency inversion principle

## 3. Detection Heuristics
- Look for variable or property declarations where the initializer is a direct call to a concrete type's initializer (e.g., `MyModel()`)
- Exclude value types (structs/enums) if desired, or focus on class types
- Exclude cases where the type is a protocol or generic

## 4. Model Changes
- Add a new case to `ArchitectureIssueType`: `case directInstantiation`
- Optionally, add a new `RuleIdentifier` for direct instantiation

## 5. Visitor Logic
- In the relevant visitor (e.g., `ArchitectureVisitor`), traverse variable/property declarations
- If the type is a concrete class and the initializer is a direct call, emit an `ArchitectureIssue` of type `.directInstantiation`
- Example pseudocode:
  ```swift
  if let variableDecl = node as? VariableDeclSyntax,
     variableDecl.type.isConcreteClass,
     variableDecl.initializer.isDirectInit {
      // Emit issue
  }
  ```

## 6. Pattern Registration
- Register a new `SyntaxPattern` for direct instantiation in `ArchitecturePatternRegistrar`

## 7. Testing
- Add test cases with direct instantiation and with dependency injection
- Ensure only the former is flagged

## 8. References
- [Swift Dependency Injection](https://www.swiftbysundell.com/articles/dependency-injection-in-swift/)
- [SOLID Principles in Swift](https://www.avanderlee.com/swift/solid-principles/) 