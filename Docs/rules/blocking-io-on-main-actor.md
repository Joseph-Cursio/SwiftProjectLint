[← Back to Rules](RULES.md)

## Blocking I/O On Main Actor

**Identifier:** `Blocking I/O On Main Actor`
**Category:** Performance
**Severity:** Warning

### Rationale
Swift 6 strict concurrency makes a data race a compile error, but it does not limit how long code holds the main actor. A synchronous file read in a `@MainActor` view model compiles cleanly and freezes the UI until the disk answers. A synchronous network request can hold it for seconds, long enough for the system watchdog to kill the app. That is a hang, not a race, and the type checker doesn't look for hangs.

The gap matters more from Swift 6.2 on. Xcode 26 app targets default to main-actor isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, SE-0466), so code with no annotation runs on the main actor unless someone moves it off.

### What counts as running on the main actor
The rule tracks isolation the way the compiler does: scope by scope. A member takes its type's isolation unless it opts out. A nested type does **not** take its outer type's.

- **Default MainActor isolation.** In a target built with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Xcode) or `swiftSettings: [.defaultIsolation(MainActor.self)]` (SwiftPM), code that says nothing runs on the main actor. The rule reads both build settings; see [Where default isolation is read](#where-default-isolation-is-read).
- **`@MainActor`** on a type, an extension, a function, an initializer or a property.
- **SDK types that are `@MainActor`.** A type conforming to `View`, `App`, `Scene`, `ViewModifier` or the `…Representable` protocols, or to an app or scene delegate protocol. A subclass of `UIViewController`, `UIView`, `NSViewController`, `NSView`, `NSWindowController`, the hosting controllers, or any other `UIResponder`/`NSResponder`.
- **The project's own `@MainActor` declarations, across files.** A conformance to a `@MainActor` protocol. A subclass of a project class that is `@MainActor`, at any depth. An `extension` of any of these, even when the type is declared in another file.
- **Conformances through a composition `typealias`.** `struct ContentView: TestableView`, with `typealias TestableView = View & ViewInspectorHook`, conforms to `View` and runs on the main actor. Each protocol the alias composes counts, as if it were written out.
- **Closures that run on the main actor wherever they are written.** `MainActor.run { }`, `MainActor.assumeIsolated { }`, `DispatchQueue.main.async/sync/asyncAfter { }`, `OperationQueue.main.addOperation { }`, and `{ @MainActor in }`.
- **`@Observable` and `ObservableObject` models**, even without `@MainActor` (and outside a MainActor-default target), but only their *synchronous* members. SwiftUI calls those from the main actor: a button action, `onAppear`, a `body` read. An unannotated model's `async` methods and `Task { }` blocks run on the global executor, so they are not reported. [Observable Main Actor Missing](observable-main-actor-missing.md) and [Main Actor Missing On UI Code](main-actor-missing-on-ui-code.md) ask for the annotation itself.

Two things people expect to move work off the main actor do not:
- **`async`.** A `@MainActor` async function still runs on the main actor between suspension points, so a synchronous read inside it blocks.
- **`Task { }`.** It inherits the enclosing actor.

The rule treats these as leaving the main actor:
- `actor` types, and types or members isolated to another global actor.
- `nonisolated` and `@concurrent` members, and non-`isolated` `deinit`.
- `Task.detached { }`, `DispatchQueue.global().async { }` and any other non-main queue's `async`, `addTask { }`, `Thread.detachNewThread { }`, URLSession completion handlers, and `{ @Sendable in }` / `{ @concurrent in }` closures.

A closure passed to any other API is assumed to run where it was written.

### What counts as blocking
| Kind | Calls |
|------|-------|
| File read | `Data`, `NSData`, `String`, `NSString`, `NSArray`, `NSDictionary`, `UIImage`, `NSImage` and `XMLParser` initialized with `contentsOfFile:`; `FileManager.contents(atPath:)`; `FileHandle.readToEnd()`, `readDataToEndOfFile()`, `readData(ofLength:)`, `read(upToCount:)` |
| URL load | The same initializers with `contentsOf:`. A URL in a variable named `url` could point at a file or a server, and either way the call blocks until the whole resource arrives |
| File write | `write(to:…)` and `write(toFile:…)` on `Data` / `String` |
| File system | `contentsOfDirectory(atPath:)`, `contentsOfDirectory(at:…)`, `subpathsOfDirectory(atPath:)`, `subpaths(atPath:)`, `copyItem(at:to:)`, `copyItem(atPath:toPath:)` |
| Network | The `contentsOf:` initializers when the URL reads as remote (`URL(string: "https://…")`, a name like `apiURL`); `NSURLConnection.sendSynchronousRequest` |
| Wait | `wait()`, `wait(timeout:)` and `wait(wallTimeout:)` on a semaphore, group or work item; `Process.waitUntilExit()`; `waitUntilAllOperationsAreFinished()`; `waitUntilFinished()` |
| Sleep | `sleep(_:)`, `usleep(_:)` |

An `await`ed call is never reported. It suspends instead of blocking, so an injected async file store is fine.

### Left to the rule that already reports it
Some blocking calls are already reported everywhere they appear by another rule. This rule skips those, so a call on the main actor gets one finding:

- **`Data(contentsOf:)` with a remote-looking URL** belongs to [Synchronous Network Call](synchronous-network-call.md). A local or ambiguous URL is reported here, because that rule skips it.
- **`Thread.sleep(...)`** belongs to [Thread Sleep](thread-sleep.md). The C `sleep`/`usleep` are reported here.
- **A semaphore wait in an async function or closure that also creates the `DispatchSemaphore`** belongs to [Dispatch Semaphore in Async](dispatch-semaphore-in-async.md). A wait in synchronous main-actor code, or on a semaphore stored elsewhere, is reported here.

[Expensive Operation in View Body](expensive-operation-in-view-body.md) reports CPU work in `body`, such as `sorted` and `filter`, and doesn't overlap with this rule's I/O and waits. [Unabstracted File IO](unabstracted-file-io.md) can fire on the same line in a `…ViewModel`, but for a different reason: it asks for a seam so the model can be tested. A seam alone doesn't fix this rule's finding, because a synchronous seam called on the main actor still blocks it. Make the seam `async` and await it.

### Where default isolation is read
The setting lives in the build configuration, not the source, so the rule reads it from both build systems under the analysed folder. A file counts if either one compiles it with the setting.

- **SwiftPM:** a target in the root `Package.swift` or a nested package's whose `swiftSettings` contain `.defaultIsolation(MainActor.self)`. The setting can be written inline, or through a top-level `let` the manifest declares (`let uiSettings: [SwiftSetting] = [...]`, including `base + [...]`). The target's files are those under its `path:`, or `Sources/<name>` without one.
- **Xcode:** a native target whose build settings, or the project's, set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Its files are the folders it synchronizes (Xcode 16 and later) and the files its Sources build phase lists.

Not read: settings from `.xcconfig` files, a synchronized folder's per-target exceptions, a manifest that sets `swiftSettings` in a loop after creating the package, and SwiftPM's other default source folders (`Source/`, `src/`). The manifest is read as text, with comments and strings handled, so the setting must be spelled out, not assembled by a function.

### Known Limitations
- **Receivers are matched by method name, not type.** `contentsOfDirectory(atPath:)` is assumed to be `FileManager`, and `wait()` a blocking wait. An `async` method with the same name is fine as long as it is awaited.
- **Closures passed to other APIs are assumed to run in place.** A completion handler that an API calls on a background queue, other than the URLSession ones above, is reported as if it ran on the main actor. Mark it `@Sendable` or suppress it with `// swiftprojectlint:disable:next blocking-io-on-main-actor`.
- **Only synchronous `@Observable`/`ObservableObject` members are inferred.** With Swift 6.2's `NonisolatedNonsendingByDefault`, an unannotated model's `async` method runs on its caller's actor, often the main one. The rule can't see that setting, so those calls are not reported.
- **Types are matched by simple name.** Two types with one name in different modules share an entry.

### Non-Violating Examples
```swift
@MainActor @Observable
final class ReceiptViewModel {
    var text = ""
    private let store: any ReceiptStore      // an actor or @concurrent API

    func loadReceipt() async {
        text = await store.receiptText()     // awaited: suspends, does not block
    }
}

actor DiskReceiptStore: ReceiptStore {
    func receiptText() -> String {           // runs on the actor, not the main actor
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}

@MainActor final class Importer {
    func importFile(at url: URL) async throws -> Data {
        try await Task.detached { try Data(contentsOf: url) }.value
    }
}
```

### Violating Examples
```swift
@MainActor @Observable
final class ReceiptViewModel {
    func loadReceipt() {
        let data = try? Data(contentsOf: receiptURL)    // reads a file on the main actor
    }
}

struct LicenseView: View {
    var body: some View {
        Text((try? String(contentsOf: licenseURL, encoding: .utf8)) ?? "")   // every render
    }
}

@MainActor final class Exporter {
    func export() {
        Task {
            try? data.write(to: exportURL)   // Task { } inherits the main actor
        }
    }
}

final class ToolRunner: ObservableObject {
    func run() {
        process.launch()
        process.waitUntilExit()               // a button action waits on a child process
    }
}
```

### How to Fix
Move the work off the main actor and `await` its result:

- Put the I/O in an `actor`, or in a `@concurrent` function (Swift 6.2), and call it with `await`.
- Use an async API: `URLSession.shared.data(from:)`, `FileHandle.bytes`, `URL.resourceBytes`.
- For a one-off, `try await Task.detached { … }.value`.
- Replace a semaphore or group wait with `withCheckedContinuation` around the callback.
- Replace `sleep`/`usleep` with `try await Task.sleep(for:)`.
