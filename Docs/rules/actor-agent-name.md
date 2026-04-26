[← Back to Rules](RULES.md)

## Actor Agent Name

**Identifier:** `Actor Agent Name`
**Category:** Code Quality
**Severity:** Info

### Rationale
A Swift `actor` named `VectorStore` or `KnowledgeGraph` gives no indication at a call site that it is an isolated concurrent agent. A reader or LLM seeing a parameter typed as `VectorStore` has no signal that calling its methods needs `await`, that its state is serialised, or that passing its internals across boundaries requires `Sendable` conformance. Names that convey active behavior — through an English agent-noun suffix or the explicit `Actor` suffix — make the isolation semantics self-evident.

### Discussion
`NamingConventionVisitor` fires this rule when an `actor` declaration's name:
- does **not** end with a recognised English agent-noun suffix (`-er`, `-or`, `-ar`), **and**
- does **not** end with `Actor`

Agent-noun suffixes (`-er`/`-or`) are the English grammatical marker for "the thing that does X" — `Indexer`, `Dispatcher`, `Migrator`, `Router`. These names already convey active behavior, so they satisfy this rule even without the `Actor` suffix. Types like `VectorStore`, `KnowledgeGraph`, or `BeadStore` sound like passive data structures and give no hint of isolation.

This rule is the semantic floor. Its stricter sibling, **Actor Naming Suffix**, requires the explicit `Actor` suffix on *all* actors regardless of whether the name already conveys agency.

**Test / fixture / example files are exempted** via the
`BasePatternVisitor.isTestOrFixtureFile()` heuristic (paths under
`Tests/`, `Examples/`, `Mocks/`, etc.). Test-scoped actors are
typically 5-10-line fixtures where the verbose suffix doesn't pay
off at the call site. The sibling **Actor Naming Suffix** rule
applies the same exemption.

### Non-Violating Examples
```swift
// Agent-noun name (-er suffix) — conveys agency
actor WorkspaceIndexer { }

// Agent-noun name (-or suffix) — conveys agency
actor SkillMigrator { }

// Explicit Actor suffix — always satisfies both rules
actor VectorStoreActor { }
actor KnowledgeGraphActor { }
```

### Violating Examples
```swift
// Passive noun — sounds like a data structure, not an isolated agent
actor VectorStore { }

// Proper noun with no agency signal
actor KnowledgeGraph { }

// Compound passive noun
actor BeadStore { }
```

---
