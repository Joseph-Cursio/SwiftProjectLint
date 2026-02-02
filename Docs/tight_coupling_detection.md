# Detecting Tight Coupling in SwiftProjectLintCore

> **Status**: Partially Implemented
>
> Circular dependency detection is implemented. The three sub-concerns listed below are proposals not yet implemented.

**Note:** Tight coupling detection is split into three separate concerns:

1. Direct Instantiation
2. Concrete Type Usage
3. Accessing Implementation Details

For implementation plans and technical details, see the dedicated markdown documents for each concern in this folder.

---

## Circular Dependency Detection (Related Concern)

Circular dependency is a specific form of tight coupling where two or more components depend on each other in a cycle (e.g., A → B → A or longer cycles). This is a well-known architectural anti-pattern that can lead to maintenance issues, runtime errors, and data flow problems.

**Status in SwiftProjectLintCore:**
- Circular dependency detection is already implemented in the codebase.
- The `ArchitectureIssueType` enum includes a `.circularDependency` case.
- The analysis logic identifies cycles in the view or module dependency graph and reports them as `ArchitectureIssue` instances.
- Both simple bi-directional references (A ↔ B) and longer cycles (A → B → C → A) are detected.

**Next Steps:**
- If you want to distinguish between bi-directional references and longer cycles, consider extending the reporting logic.
- For more details or enhancements, see the relevant visitor and model code in the `Architecture` module.

--- 