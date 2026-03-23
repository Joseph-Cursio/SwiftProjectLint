[← Back to Rules](RULES.md)

## Unknown

**Identifier:** `Unknown`
**Category:** Other
**Severity:** Warning

### Rationale
A fallback rule identifier used when an issue is generated without a specific `RuleIdentifier`. This should not appear in normal operation and indicates an internal inconsistency in the analysis pipeline.

### Discussion
`RuleIdentifier.unknown` is used in placeholder `SyntaxPattern` instances created by visitor convenience initializers and in code paths that call `addIssue(ruleName: nil)`. If issues with this identifier appear in results, they point to analysis code that has not yet been assigned a proper rule identifier.

---
