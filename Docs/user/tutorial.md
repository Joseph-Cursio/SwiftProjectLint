# SwiftProjectLint Tutorial

This tutorial walks through a complete analysis of a SwiftUI project — from first run to a clean build with a configuration file in place.

---

## Before You Start

Build the CLI tool:

```bash
cd /path/to/SwiftProjectLint
swift build -c release
cp .build/release/CLI /usr/local/bin/swiftprojectlint
```

You'll need a SwiftUI project to analyze. The examples below use a hypothetical project at `~/Developer/MyApp`.

---

## Step 1: First Run

Run the tool with no configuration:

```bash
swiftprojectlint ~/Developer/MyApp
```

You'll see output like this:

```
ContentView.swift:8 [Warning] Fat View: View body exceeds recommended complexity.
  → Extract subviews or move logic to a ViewModel.

NetworkManager.swift:22 [Error] Hardcoded Secret: API key found in source code.
  → Move sensitive data to environment variables or a secrets manager.

UserListView.swift:15 [Warning] ForEach Without ID: Array used in ForEach without an explicit ID.
  → Add .id or use a type conforming to Identifiable.

UserListView.swift:31 [Warning] Force Try: Avoid force try expressions that can crash at runtime.
  → Use do/catch to handle errors gracefully.

ProfileView.swift:44 [Info] Magic Number: Hardcoded numeric literal 16.
  → Define a named constant.

Found 5 issues (1 error, 3 warnings, 1 info)
```

The exit code is non-zero because there are warnings. In a CI script, this would fail the build.

---

## Step 2: Focus on What Matters First

Too many issues at once? Limit to a single category:

```bash
swiftprojectlint ~/Developer/MyApp --categories security
```

```
NetworkManager.swift:22 [Error] Hardcoded Secret: API key found in source code.
  → Move sensitive data to environment variables or a secrets manager.

Found 1 issue (1 error)
```

Fix the hardcoded secret, then move on to the next category.

---

## Step 3: Fix an Issue

The `Force Try` violation in `UserListView.swift:31` is straightforward. The offending code:

```swift
let items = try! JSONDecoder().decode([Item].self, from: data)
```

Replace it with proper error handling:

```swift
do {
    let items = try JSONDecoder().decode([Item].self, from: data)
    self.items = items
} catch {
    self.errorMessage = error.localizedDescription
}
```

Run again to confirm it's gone:

```bash
swiftprojectlint ~/Developer/MyApp --categories codeQuality
```

---

## Step 4: Suppress a Legitimate False Positive

The `Magic Number` warning on `ProfileView.swift:44` flags a standard spacing constant you deliberately want to keep as a literal:

```swift
.padding(16)
```

Suppress just that line:

```swift
.padding(16) // swiftprojectlint:disable:this magic-number
```

Or suppress the next line instead (useful when the comment reads more naturally above):

```swift
// swiftprojectlint:disable:next magic-number
.padding(16)
```

---

## Step 5: Create a Configuration File

Once you know which rules and paths make sense for your project, codify that in a `.swiftprojectlint.yml` file at the project root.

Create `~/Developer/MyApp/.swiftprojectlint.yml`:

```yaml
# Rules that generate too much noise for this project right now
disabled_rules:
  - "Missing Documentation"
  - "Magic Number"

# Skip generated code and test fixtures
excluded_paths:
  - "Generated/"
  - "Mocks/"
  - "TestFixtures/"

# Downgrade this to info — it's a guideline, not a hard rule here
rules:
  "Fat View":
    severity: info

  # This rule is valid, but not for our legacy views folder
  "Force Try":
    excluded_paths:
      - "LegacyViews/"
```

Now run without any flags:

```bash
swiftprojectlint ~/Developer/MyApp
```

The tool automatically finds and loads `.swiftprojectlint.yml`.

---

## Step 6: Add to CI

In a GitHub Actions workflow:

```yaml
- name: SwiftProjectLint
  run: |
    swift build -c release --package-path /path/to/SwiftProjectLint
    /path/to/SwiftProjectLint/.build/release/CLI ${{ github.workspace }} --threshold error
```

Using `--threshold error` means the build only fails for errors, not warnings — useful while you're incrementally fixing issues.

For structured output that a downstream step can parse:

```yaml
- name: SwiftProjectLint (JSON)
  run: |
    .build/release/CLI ${{ github.workspace }} --format json > lint-results.json || true
```

---

## Step 7: Explore the Rules

Each rule has a dedicated doc in `docs/rules/`. Start with the index:

```
docs/rules/RULES.md
```

For example, `docs/rules/force-try.md` explains exactly what pattern is detected, why it matters, and shows both violating and non-violating code examples.

---

## Next Steps

- Browse `docs/rules/RULES.md` to discover rules you haven't encountered yet
- Use `--categories` to audit one area at a time
- Read `docs/reference.md` for the complete CLI and configuration schema
