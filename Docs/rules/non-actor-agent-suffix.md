[← Back to Rules](RULES.md)

## Non-Actor Agent Suffix

**Identifier:** `Non-Actor Agent Suffix`
**Category:** Code Quality
**Severity:** Info
**Default:** Opt-in (disabled by default)

### Rationale
When a class or struct carries an English agent-noun name — `DataManager`, `FileProcessor`, `NetworkRouter` — the name implies that the type *does something*. Readers and LLMs expect an active agent. But unlike a Swift `actor`, a plain class or struct provides no compiler-enforced isolation. The name creates an expectation the declaration does not fulfill.

This opt-in rule asks you to be explicit: either promote the type to a Swift `actor` (gaining compiler-enforced isolation) or append `Agent` to the name, openly declaring that this is a non-isolated agent whose thread safety you manage manually.

### Discussion
`NamingConventionVisitor` fires this rule when:
- A `class` or `struct` name ends in a recognised English agent-noun suffix (`-er`, `-or`, `-ar`), **and**
- The name does **not** end with `Agent`

**Property wrappers are exempt.** Types marked `@propertyWrapper` follow the `Wrapper` naming convention, which incidentally ends in `-er`. They are skipped by this rule.

This rule is opt-in because many codebases use agent-noun names on plain classes intentionally and without confusion. Enable it in `.swiftprojectlint.yml` when you want to enforce a strict naming contract across your team:

```yaml
enabled_only:
  - Non-Actor Agent Suffix
```

### Non-Violating Examples
```swift
// Explicit Agent suffix — declares intentional non-isolation
class DataManagerAgent { var items: [String] = [] }
struct FileProcessorAgent { var path: String = "" }

// Swift actor — compiler-enforced isolation; satisfies the semantic intent
actor DataManager { var items: [String] = [] }

// Non-agent-noun name — no expectation of active behavior
class VectorStore { }
struct KnowledgeGraph { }

// Property wrapper — exempt
@propertyWrapper struct ClampedWrapper<Value: Comparable> { var wrappedValue: Value }
```

### Violating Examples
```swift
// Agent-noun class with no isolation signal
class DataManager { var items: [String] = [] }

// Agent-noun struct — structs are value types but the name still implies active behavior
struct FileProcessor { var path: String = "" }

// -or suffix
class NetworkRouter { }

// -ar suffix
class FileRegistrar { }
```

---
