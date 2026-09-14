[← Back to Rules](RULES.md)

## Implicit Codable Raw Value

**Identifier:** `Implicit Codable Raw Value`
**Category:** Code Quality
**Severity:** Info

### Rationale

A String-backed enum's synthesized `Codable` conformance encodes each case as its raw value. A case without an explicit raw value takes its own name as the raw value. So for such an enum, the stored and transmitted format *is* the list of case names.

That makes renaming a case a breaking change that nothing catches:

```swift
enum Status: String, Codable {
    case active
    case disabled   // was `case inactive`
}
```

This compiles, and every test that encodes and decodes through the current code still passes. But every `"inactive"` already on disk, in a cache, in `UserDefaults` or in a server response now fails to decode, and it fails at runtime, in production, on data you can't easily migrate.

An explicit raw value separates the Swift name from the stored format, so the case can be renamed freely:

```swift
enum Status: String, Codable {
    case active = "active"
    case disabled = "inactive"
}
```

#### If you use SwiftLint

SwiftLint's default rule `redundant_string_enum_value` reports exactly that fix: an explicit raw value equal to the case name. If you run both tools, pin the raw values in a test instead. The test fails when a case is renamed or its value is edited, which gives the same protection:

```swift
@Test func statusWireFormat() {
    #expect(Status.allCases.map(\.rawValue) == ["active", "inactive"])
}
```

Then exclude the file from this rule in `.swiftprojectlint.yml`, noting where the test is:

```yaml
rules:
  "Implicit Codable Raw Value":
    excluded_paths:
      - "Models/Status.swift"   # raw values pinned by StatusWireFormatTests
```

Prefer the config exclusion to an inline `swiftprojectlint:disable` comment, which the [SwiftProjectLint Suppression](swiftprojectlint-suppression.md) rule reports as a warning.

### Discussion

`ImplicitCodableRawValueVisitor` reports an enum when all of the following are true:

- its raw type, which Swift requires to be first in the inheritance clause, is `String`;
- it conforms to `Codable`, `Encodable` or `Decodable`, either in its declaration or through an extension in the same file;
- at least one of its cases has no explicit raw value, including cases inside `#if` blocks.

It is reported once per enum, at its name, listing up to three of the cases that need a value. The severity is Info, not Warning: the defect stays hidden until someone renames a case, and a new warning-level rule would fail the CLI's default threshold on every existing codebase that has such an enum.

SwiftLint's opt-in `explicit_enum_raw_value` asks for explicit raw values on every enum. This rule is limited to `Codable` enums, because conforming to `Codable` is what signals that the raw value leaves the process.

### Not Reported

- **Test and fixture files.** An enum that is only encoded and decoded inside a test run has no stored values to break.
- **Enums that implement `init(from:)` or `encode(to:)` themselves**, in the enum body or in a same-file extension. Their format is hand-written and may not use the raw value.
- **`CodingKey` enums** (`enum CodingKeys: String, CodingKey`). They aren't `Codable`, and their implicit values deliberately track the property names.
- **Integer-backed enums.** Their implicit values come from case order, so the hazard is reordering rather than renaming. Many of them are never meant to be stable, so they're left out.
- **Conformance the rule cannot see**: `Codable` added by an extension in another file, or inherited through a protocol that refines it.

### Non-Violating Examples

```swift
enum Status: String, Codable {
    case active = "active"
    case inactive = "inactive"
}

enum Tab: String, CaseIterable {   // not Codable
    case home, settings
}
```

### Violating Examples

```swift
enum Status: String, Codable {
    case active                     // ← encodes as "active" only because of its name
    case inactive = "inactive"
}
```

---
