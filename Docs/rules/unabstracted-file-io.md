[← Back to Rules](RULES.md)

## Unabstracted File IO

**Identifier:** `Unabstracted File IO`
**Category:** Architecture
**Severity:** Info

### Rationale
An orchestration type — a `…Model`, `…ViewModel`, or `…Service` whose job is to coordinate work and whose other dependencies are already injected — defeats its own testability the moment it reaches straight for the filesystem. A call like `String(contentsOfFile:)` or `someText.write(to:)` welds the type to real files on disk: a unit test can no longer exercise the surrounding logic without staging fixture files and tolerating I/O failure modes that have nothing to do with the behaviour under test. This is the dual of [Concrete Type Usage](concrete-type-usage.md): that rule flags a *property or parameter* typed as a concrete service class, whereas this one flags the raw I/O *call* that has no type annotation to catch but is exactly the dependency that should sit behind an injected seam.

The fix is small and idiomatic: declare a narrow protocol for the file access (a `…Reading` / `…Writing` seam), give the type a stored property of that protocol type supplied through its initializer (defaulting to the real Foundation-backed implementation), and call the seam here instead. Tests then inject a lightweight in-memory conformer and never touch disk.

### Discussion
`UnabstractedFileIOVisitor` tracks the enclosing type via a declaration stack so the *innermost* type decides scope, and fires only when that type's name ends in `Model`, `ViewModel`, or `Service`. This allowlist is deliberately narrow to stay high-precision: types that *are* the I/O seam — `…Reader`, `…Writer`, `…Store`, `…Actor`, a CLI's `…Linter`, a composition root — never carry those suffixes, so the raw I/O that is their whole purpose is left alone. Test and fixture files are exempt.

The matched calls are:

- **Reads:** `String(contentsOfFile:)`, `String(contentsOf:)`, `Data(contentsOfFile:)`, `Data(contentsOf:)` — a `String`/`Data` initializer whose first argument label is `contentsOf` or `contentsOfFile`.
- **Writes:** `<value>.write(to:)` — Foundation's `String`/`Data` write, identified by `to` being the call's *first* argument label. A static call to an injected writer helper such as `SafeFileWriter.write(text, to:)` passes the content as an unlabeled first argument, so it is correctly **not** flagged — that call is already a seam.

Because the rule keys off both the call shape and the enclosing type's role, it catches a missed seam that the type-annotation rules cannot see (the I/O is a bare function call, not a typed dependency), while staying silent on the layers where raw I/O belongs.

**Scope note:** the rule reasons about a single file's syntax; it does not verify that the enclosing type actually injects its *other* dependencies. The suffix allowlist is the heuristic standing in for "this is an orchestration layer that should delegate I/O."

### Non-Violating Examples
```swift
// The seam type itself performs the raw I/O — that is its job.
struct FileSystemSourceReader: SourceFileReading {
    func readSource(at path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }
}

// The model delegates through an injected seam.
final class ImpactModel {
    private let reader: any SourceFileReading
    func ruleDiff(filePath: String) throws -> String {
        try reader.readSource(at: filePath)
    }
}

// Writing through an injected helper — content is the unlabeled first argument.
final class ConfigModel {
    func save(text: String, to url: URL) throws {
        try SafeFileWriter.write(text, to: url, createBackup: true)
    }
}
```

### Violating Examples
```swift
// Raw read inline inside an orchestration model.
final class ImpactModel {
    func ruleDiff(filePath: String) -> String {
        guard let source = try? String(contentsOfFile: filePath, encoding: .utf8) else { return "" }
        return source
    }
}

// Raw write inline inside a model — String.write(to:).
final class ConfigModel {
    func save(text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
```

### How to Fix
Define a protocol describing the file access the type needs, inject it through the initializer with a Foundation-backed default, and replace the inline call with a call to the injected seam:

```swift
public protocol SourceFileReading: Sendable {
    func readSource(at path: String) throws -> String
}

public struct FileSystemSourceReader: SourceFileReading {
    public init() {}
    public func readSource(at path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }
}

final class ImpactModel {
    private let reader: any SourceFileReading
    init(reader: any SourceFileReading = FileSystemSourceReader()) {
        self.reader = reader
    }
}
```

Once the model reads through `reader`, the rule stops firing and the type becomes unit-testable with an in-memory conformer.
