[← Back to Rules](RULES.md)

## Synchronous Network Call

**Identifier:** `Synchronous Network Call`
**Category:** Networking
**Severity:** Error

### Rationale
`Data(contentsOf: url)` performs a synchronous network request on the calling thread. When called on the main thread with a remote URL, this blocks the UI for the full duration of the network round trip — potentially several seconds — causing the app to become unresponsive and the system watchdog to terminate it.

However, `Data(contentsOf:)` is perfectly appropriate for reading local files. The rule distinguishes between the two.

### Scope
- Flags `Data(contentsOf:)` when the URL argument appears to be a remote or ambiguous URL
- Does **not** flag calls where the URL is constructed with `URL(fileURLWithPath:)` or `URL(filePath:)`
- Does **not** flag calls where the URL comes from `.appendingPathComponent()` or `.appending()` chains
- Does **not** flag calls where the URL comes from `Bundle.main`
- Does **not** flag calls where the variable name suggests a local file (contains "file", "path", "cache", "temp", "directory", "folder", or "config")
- Does **not** flag `Data()` or `Data([1, 2, 3])` — only the `contentsOf:` label triggers the check

### Known Limitation
When the URL is stored in a generically-named variable (e.g., `url`) that actually points to a local file, the rule cannot determine this statically and may still flag it.

### Non-Violating Examples
```swift
// Async with URLSession — correct approach for remote data
Task {
    let (data, _) = try await URLSession.shared.data(from: url)
}

// Local file reads — Data(contentsOf:) is fine here
let data = try Data(contentsOf: URL(fileURLWithPath: "/tmp/data.json"))
let data = try Data(contentsOf: cacheFilePath)
let data = try Data(contentsOf: dir.appendingPathComponent("rules.json"))
let data = try Data(contentsOf: Bundle.main.url(forResource: "data", withExtension: "json")!)
let data = try Data(contentsOf: tempURL)

// Data() without contentsOf — fine
let emptyData = Data()
let fixedData = Data([1, 2, 3])
```

### Violating Examples
```swift
let url = URL(string: "https://example.com")!
let data = try Data(contentsOf: url)  // synchronous network call — blocks main thread
```

---
