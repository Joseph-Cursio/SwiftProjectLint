[← Back to Rules](RULES.md)

## Unconditional Trap

**Identifier:** `Unconditional Trap`
**Category:** Code Quality
**Severity:** Warning

### Rationale
`fatalError()` and `preconditionFailure()` take no condition: reaching the line *is* the failure, so the function has no answer for whatever input got it there. That makes the function partial at exactly that point, and the failure arrives as a fatal signal rather than a value, so a property run ends instead of producing a counterexample.

### Discussion
`UnconditionalTrapVisitor` matches calls to `fatalError` and `preconditionFailure` only.

Three deliberate exclusions:

- **`precondition` and `assert` are not flagged.** They take a condition and usually encode a contract the function genuinely depends on. Flagging them would ask the author to weaken a real invariant to satisfy a linter. Where such a contract blocks property testing, the fix is to narrow the *input type* until the check cannot fail — then the check is deletable rather than suppressed.
- **`assertionFailure` is not flagged.** It is compiled out of release builds, so it is a debug aid rather than a statement about the function's domain.
- **`required init?(coder:)` is exempt.** Xcode's own template writes `fatalError` into that body, no property test will ever call it, and no refactor removes it.

The fix is often not a change of return type. A `fatalError` in a `default:` case over a closed enum goes away by deleting the `default` and handling the cases: the signature is untouched, the trap becomes unreachable by proof, and the next person to add a case gets a build failure instead of a dead process.

```swift
// Before
func symbol(for status: Status) -> String {
    switch status {
    case .ok: return "ok"
    case .warning: return "warn"
    default: fatalError("unhandled status \(status)")
    }
}

// After
func symbol(for status: Status) -> String {
    switch status {
    case .ok: return "ok"
    case .warning: return "warn"
    case .failed: return "failed"
    }
}
```

### Non-Violating Examples
```swift
// Conditional contract — not flagged
precondition(!values.isEmpty, "average of nothing is undefined")
assert(index < count)

// Debug-only, compiled out of release
assertionFailure("unexpected state")

// Required by NSCoding, exempt
required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
}
```

### Violating Examples
```swift
// Unconditional traps — the process ends here
default: fatalError("unhandled status")
guard let first = values.first else { preconditionFailure("empty") }
```

---
