[← Back to Rules](RULES.md)

## Protocol Naming Suffix

**Identifier:** `Protocol Naming Suffix`
**Category:** Code Quality
**Severity:** Info
**Default:** Opt-in (disabled by default)

### Rationale
Some teams give every protocol a `Protocol` suffix, so that a type's role shows wherever it is named: a parameter typed `NetworkServiceProtocol` can't be mistaken for a class. This rule enforces that convention for a team that has chosen it.

It is a team convention, not a design principle, so it is off by default. To enable it, list it under `enabled_only` in `.swiftprojectlint.yml`. `enabled_only` runs only the rules it names, so add it to the list you already have:

```yaml
enabled_only:
  - Protocol Naming Suffix
```

### Why it is opt-in
The rule used to run by default. On Checkout, a default run reported `OrderStore`, a protocol whose one conformer is `CoreDataOrderStore` and whose every use is written `any OrderStore`, and asked for `OrderStoreProtocol`. Three things argue against making that the default.

**Swift's guidelines name protocols the other way.** The [API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) say a protocol that describes what something *is* should read as a noun (`Collection`), and one that describes a capability should end in `-able`, `-ible` or `-ing` (`Equatable`, `ProgressReporting`). The standard library uses `Protocol` only where the noun is already taken: `IteratorProtocol`, because `Iterator` is `Sequence`'s associated type, and `StringProtocol`, because `String` is the concrete type.

**The suffix leads toward the pairing that [Mirror Protocol](mirror-protocol.md) inspects.** In practice the suffix frees the bare name for an implementation: first `OrderStoreProtocol`, then a class called `OrderStore`. In the corpus measured below, 27 of the 47 production protocols that already end in `Protocol` sit beside a type named for the stem, including 17 of 19 in SwiftLintRuleStudio, and this repository's own `SourcePatternDetectorProtocol`, whose only conformer is `SourcePatternDetector`. The two rules never report the same protocol: this one fires only on unsuffixed names, and Mirror Protocol only on suffixed ones. But a default run that asked for the suffix was asking for the first half of the shape another default rule questions.

**The use site already shows the abstraction.** `any OrderStore`, `some OrderStore` and `<Store: OrderStore>` each say "protocol" where the type is used, which is what the suffix was for, and the `ExistentialAny` upcoming feature makes `any` mandatory. The linter doesn't need the suffix either: [Concrete Type Usage](concrete-type-usage.md) recognises any protocol the project declares.

The suffix does have one real benefit. Xiangyu Sun's article [*How Well Can You Detect a Swift Protocol Without the Compiler?*](https://medium.com/ios-ic-weekly/how-well-can-you-detect-a-swift-protocol-without-the-compiler-537fac929bd7) (featured in [Fatbobman's Swift Weekly #127](https://weekly.fatbobman.com/p/fatbobmans-swift-weekly-127)) shows that it is one of the most reliable signals for a static tool or an LLM to recognise a protocol without compiler access. That is a fair reason for a team to opt in, but not a reason to ask every project to rename.

### Measured
A default run (no configuration file) over 35 Swift repositories, first-party and cloned third-party, each at its default branch on 2026-10-07. A fork that duplicates another repository's sources is counted once.

- **48 findings** out of 14,198 issues in total, in 15 of the 35 repositories.
- **26 of the 48 are role nouns whose conformers carry the name or its last word**: `TokenStore` (`InMemoryTokenStore`, `KeychainService`), `ArchiveBackend` (`OCIArchiveBackend`, `ZipArchiveBackend`), `SyncAdapter` (`GitAdapter`, `ICloudDriveAdapter`).
- Most of the other 22 are role nouns too, with conformers named differently: `ParsedWrapper` (`Argument`, `Flag`, `Option`), `RunCommand` (`Run`, `RunWithoutMutating`). Four have no conformer in the repository.

### Why not exempt role nouns instead
The alternative was to keep the rule on by default and skip protocols whose names are role nouns with no concrete type of the same stem. It doesn't hold up.

- A protocol and a type can't share a name in one module, so no reported protocol *has* a concrete type of the same name. "Same stem" would have to be guessed from qualifiers like `Default`, `Live`, `InMemory` or `CoreData`.
- "Role noun" would also be a guess from spelling. The rule already guesses that way: its exemption list (`Provider`, `Handler`, `Delegate`, …) is a list of role nouns, and it grows by one each time someone names a protocol well.
- On the corpus, the most generous test (a conformer whose name ends in the protocol's last word) exempts 26 of the 48 findings. The other 22 are role nouns that test can't see, so the rule would stay on by default in name only.

### Discussion
`NamingConventionVisitor` checks `protocol` declarations without a `Protocol` suffix. To reduce false positives, the following are exempt:

- **Capability-describing suffixes** — names ending in `-able`, `-ible`, `-ing`, `-ive` (e.g., `Equatable`, `Collecting`, `Correctable`) already convey "this is a contract"
- **Domain-role suffixes** — `Rule`, `Configuration`, `Provider`, `Validator`, `Reporter`, `Visitor`, `Handler`, `Delegate`, `DataSource`, `Factory`, `Builder`, `Context`, `Comparable`, `Convertible`
- **Public protocols** — library API protocols follow community conventions
- **Test/example files** — exempt from naming rules

If you enable the rule, you can still stay clear of Mirror Protocol: name implementations for what they are (`actor CoreDataOrderStore: OrderStoreProtocol`), not after the protocol's stem.

### Non-Violating Examples (when enabled)
```swift
protocol NetworkServiceProtocol {
    func fetch() async throws -> Data
}

// "-able" already reads as a contract
protocol Requestable {
    func perform() async throws
}
```

### Violating Examples (when enabled)
```swift
protocol OrderStore { func save(_ order: Order) async throws }  // missing "Protocol" suffix

protocol DataStore { func save() }  // missing "Protocol" suffix
```

---
