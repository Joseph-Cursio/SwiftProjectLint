[← Back to Rules](RULES.md)

## Extractable Pure Kernel

**Identifier:** `Extractable Pure Kernel`
**Category:** Testability
**Severity:** Info

### Rationale

[Pure Function Property-Test Candidate](pure-function-candidate.md) can point at a declaration.
[Pure Closure Property-Test Candidate](pure-closure-candidate.md) can point at a closure. Neither can
see the third shape, which is the most valuable of the three: **arithmetic with no boundary drawn
around it**, inlined in a method that also does network or disk I/O.

A closure at least *exists* as a syntactic object. A kernel does not. It is a handful of statements
in the middle of a method — a subset nobody has ever named, separated from the I/O around it by
nothing at all. And because it has no boundary, every tool in the chain walks straight past it, and so
does every test.

This is worse than the closure case, not better. To test the arithmetic you must call the method that
contains it; the method is `private`, `async` and `throws`, and calling it means standing up a live
session and a server. So the part of the code that can actually be **wrong** — the counting, the
offsets, the fractions — is the part nothing can reach.

### Discussion

The case this rule was built for:

```swift
private func uploadRemainingChunks(of data: Data, session current: SyncSessionResponse,
                                   chunkSize: Int, progressHandler: ((Double) -> Void)?)
    async throws -> SyncSessionResponse {

    let totalChunks = (data.count + chunkSize - 1) / chunkSize
    var index = current.queuedChunks

    while index < totalChunks {
        let chunk = Data(data.dropFirst(index * chunkSize).prefix(chunkSize))
        _ = try await uploadChunkWithRetry(sessionId: current.id, index: index, chunk: chunk)
        index += 1
        progressHandler?(Double(index) / Double(totalChunks))
    }
    return try await completeSyncSession(id: current.id)
}
```

How many chunks are there; where does chunk *n* start and stop; how far along are we. That is a
function of `(data.count, chunkSize, index)` and nothing else — no network, no disk, no clock. It is
also where **two real bugs** were living, both invisible to every test that could be written:

- **A corrupt resume counter silently completes a partial upload.** `var index = current.queuedChunks`
  takes a number *straight from the server, unclamped*. A stale session reporting more chunks than the
  payload has makes `index < totalChunks` false immediately — the loop never runs, and the client
  calls `completeSyncSession` on a file it never finished. A negative makes `dropFirst` trap.
- **An empty file never reports completion.** `data.count == 0` ⇒ `totalChunks == 0` ⇒ the loop body
  never runs ⇒ `progressHandler` is never called, and the progress bar hangs at zero forever.

Name the arithmetic and both fall out on the first run:

```swift
struct ChunkPlan {
    let byteCount: Int
    let chunkSize: Int
    let startIndex: Int              // clamped to 0...totalChunks

    var totalChunks: Int { … }
    func range(ofChunk index: Int) -> Range<Int> { … }
    func progress(afterCompleting index: Int) -> Double { … }
}
```

Three integers, no server. Now you can state what must be true **for every** byte count, chunk size
and resume point — *the chunks tile the payload exactly*, *the resume index lies within
`0...totalChunks` whatever the server said*, *progress terminates at 1.0* — and let a generator go
looking for the ones that break. The resume property draws from −50 to 500 precisely because **that
number is not yours to trust**; it came over the network, and an example test would naturally have
picked "resume from chunk 3 of 10", because that is the case a human pictures.

**One honest caveat, because it is the sort of thing that gets oversold.** The *general* progress
property — "progress is monotonic and terminates at 1.0" — does **not** catch the empty-file bug: with
zero chunks its sample array is empty and `.last` is `nil`, so it passes vacuously. It took a property
aimed squarely at the empty case. Boundary cases still have to be named, even under PBT.

### Three gates, each put there by a finding

A kernel has no syntactic boundary, so this rule's entire worth is its **precision**. The acceptance
set was built by hand-classifying all 85 functions of a real iOS app *before* a line of the rule was
written, and each gate below exists because that audit turned up a case that needed it.

1. **The enclosing function must be impure.** A pure function has no *trapped* kernel — it **is** the
   kernel, and [Pure Function Property-Test Candidate](pure-function-candidate.md) already seeds it.
   Without this gate the rule fires on `isValidFolderName`, an already-named pure function with
   nothing to extract. A rule that re-reports another rule's findings teaches the reader that the two
   disagree.
2. **Closure bodies are skipped.** A kernel living wholly inside a `filter` predicate belongs to
   [Pure Closure Property-Test Candidate](pure-closure-candidate.md), reported once.
3. **The derivation must govern a decision.** A derived value that is merely *stored* is not a
   kernel — it has to become a **loop bound, an index, a slice range, a comparison, a membership
   test, or a progress fraction**. This is the clause that separates chunking math from a local
   variable someone extracted for readability, and it is why `navigateUp`'s pure path arithmetic is
   deliberately *not* reported (its result is assigned, not used as a bound). That shape is a
   state-machine law — `up ∘ down == id` — and it belongs to a different template.

### Two shapes, and how the second one was found

Gates 1 and 2 apply to both shapes; gate 3 is what each shape has to satisfy.

| | **Arithmetic** | **Path / string** |
|---|---|---|
| Derivation | `let total = (count + size - 1) / size` | `let prefix = root.hasSuffix("/") ? root : root + "/"` |
| Governing use | loop bound, index, slice with an operator, fraction | slice driven by a `.count`, membership test, or a comparison **naming** the binding |
| Law it owes | the parts tile the whole; progress terminates at 1.0 | the derivation round-trips; normalisation is idempotent |
| Bug it catches | off-by-one counts, unclamped resume index | off-by-one prefixes, a suffix stripped from the wrong end |

The second shape exists because the rule was run over a 60k-line linter and reported **nothing at
all** — and that silence was not "this code is clean". The linter's impure methods enumerate
directories and derive paths, and a path kernel has no operator reaching a bound, so every gate
walked past it. `dropFirst(prefix.count)` is a slice with no arithmetic in it anywhere.

Admitting it **narrows** gate 3 rather than widening it. A derived display string still does not
fire, because it governs nothing. What changed is that "governs" now includes deciding *with* a
string, not only bounding a loop with a number.

Its governing test is deliberately stricter than the arithmetic shape's. That one accepts any
comparison containing an arithmetic operator, whatever names it mentions; since `+` on strings is
concatenation, reusing it here vouched for derivations it had nothing to do with. The path shape
requires the comparison to actually name the binding.

**Measured, on two codebases:**

| Corpus | Before | After | Lost |
|---|---|---|---|
| SwiftProjectLint (876 findings) | 0 | 2 | 0 |
| SwiftInferProperties (2421 findings) | 1 | 9 | 0 |

Eight of the nine new findings are the same `findPackageRoot` walk-up, inlined in eight files. The
law is that the walk **terminates**, and it is unreachable from a test because the derivation is
welded to a hardcoded `FileManager.default`. The threshold of two derivations is a cheap guard, not
the thing providing the precision: relaxing it to one changes nothing on either corpus.

### Non-Violating Examples

```swift
// A pure function IS the kernel. Nothing is trapped; the function rule seeds it.
func chunkCount(of byteCount: Int, chunkSize: Int) -> Int {
    let total = (byteCount + chunkSize - 1) / chunkSize
    return total > 0 ? total : 1
}

// Arithmetic inside a closure — the closure rule's finding, reported once.
let children = all.filter { file in
    let depth = file.path.count - currentPath.count
    return depth > 0 && depth < 2
}

// Arithmetic that is only STORED. Real logic, but its result is assigned rather than used as a
// bound, an index, a slice or a fraction — that is a state-machine law, not a kernel.
func navigateUp() async {
    let components = currentPath.split(separator: "/")
    currentPath = "/" + components.dropLast().joined(separator: "/") + "/"
    await loadFiles()
}

// A request builder: no separable arithmetic at all.
func login(email: String, password: String) async throws -> User {
    var request = createRequest(endpoint: "/auth/login", method: "POST")
    request.httpBody = try JSONEncoder().encode(Credentials(email: email, password: password))
    let (data, response) = try await session.data(for: request)
    return try decoder.decode(User.self, from: data)
}

// A counter compared to a constant. `retries < maxRetries` decides nothing a generator could break:
// one binding, no arithmetic feeding the comparison.
var retries = 0
while true {
    do { return try await uploadChunk(index: index, data: chunk) }
    catch let error as URLError {
        guard retries < Self.maxChunkRetries else { throw error }
        retries += 1
    }
}
```

### Violating Examples

```swift
// THE motivating case. Chunk count, offsets and progress — a function of three integers, welded to a
// method that needs a live server. Two real bugs lived here, unreachable by any test.
func uploadRemainingChunks(of data: Data, from queued: Int, chunkSize: Int) async throws {
    let totalChunks = (data.count + chunkSize - 1) / chunkSize
    var index = queued
    while index < totalChunks {
        let chunk = Data(data.dropFirst(index * chunkSize).prefix(chunkSize))
        _ = try await uploadChunk(chunk)
        index += 1
        progressHandler?(Double(index) / Double(totalChunks))
    }
}

// A progress throttle inside a byte stream. The SAME defect family, one method away: if the server
// omits Content-Length then `expectedBytes <= 0` and progress is never reported at all; if it
// over-sends, progress exceeds 1.0. Generalising a bug class beats re-finding one bug.
func collect(_ bytes: URLSession.AsyncBytes, expecting expectedBytes: Int64) async throws -> Data {
    var data = Data()
    var lastReported = 0.0
    for try await byte in bytes {
        data.append(byte)
        guard expectedBytes > 0 else { continue }
        let progress = Double(data.count) / Double(expectedBytes)
        if progress - lastReported >= 0.01 {
            lastReported = progress
            progressHandler(progress)
        }
    }
    return data
}
```

### Known Limitations

- **It is not a dataflow analysis, on purpose.** A kernel has no syntactic boundary — it is whatever
  set of statements you *choose* to lift — so a precise "maximal pure set" is both hard and beside the
  point. The reader draws the boundary; the rule only has to say *there is one here, and here is what
  it is made of*. Precision comes from demanding that arithmetic reach a governing position, not from
  tracing it exactly.
- **A binding whose initialiser calls anything but a numeric conversion is not counted.** The rule
  will not vouch for work it cannot see, so a kernel assembled through a helper call is missed.
  Conservative in the direction of silence.
- **Clause 3 excludes classification whose result decides nothing.** A pure `getFileIcon(for:)`
  mapping an extension to an asset name has a law worth stating, but its result is a display string
  that is returned, not a bound, a slice or a lookup key. It is the function rule's finding, not this
  one's — and if it were inlined in an impure method, this rule still misses it.

  *Partially closed.* Classification that **governs** — `skipped.contains(dirName)` deciding whether
  to prune a subtree — is now the path shape's finding. What remains excluded is classification
  whose result is merely returned or stored.
- **The path shape needs two chained derivations.** A single one that slices is not enough. Measured
  as inert on both corpora tested, so a codebase with one-step path kernels would be missed; the
  guard is kept because it is cheap and the shapes it would admit are unmeasured.
- **Duplicated kernels are reported once per copy.** The eight `findPackageRoot` findings in
  SwiftInferProperties are eight real sites, but one refactor closes all of them. The rule has no
  cross-file identity for a kernel, so it cannot say so.

### Remediation

Lift the arithmetic into a value type built from its inputs alone. The method keeps the I/O and asks
the value type where the bytes are.

The payoff is that the logic becomes **addressable**: constructible in a test from three integers, with
no server, no session and no disk — at which point you can state the law it owes you and generate
inputs against it.

---
