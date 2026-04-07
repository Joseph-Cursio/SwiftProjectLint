# SwiftProjectLint Reference Guide

---

## CLI

### Synopsis

```
swiftprojectlint <project-path> [options]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<project-path>` | Path to the Swift project directory to analyze. Required. |

### Options

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `--format` | `text`, `json` | `text` | Output format. |
| `--threshold` | `error`, `warning`, `info` | `warning` | Minimum severity that causes a non-zero exit code. |
| `--categories` | See below | all | One or more category names (space-separated). Restricts analysis to those categories. |
| `--config` | file path | `.swiftprojectlint.yml` in project root | Path to a configuration file. |
| `--version` | — | — | Print the version number and exit. |
| `--help` | — | — | Print usage information and exit. |

### Category Names

Used with `--categories`:

| Name | Description |
|------|-------------|
| `stateManagement` | Property wrappers, duplicate state, state ownership |
| `performance` | Expensive view body operations, ForEach misuse, large views |
| `animation` | Deprecated APIs, excessive springs, animation anti-patterns |
| `architecture` | MVVM, dependency injection, coupling |
| `codeQuality` | Magic numbers, hardcoded strings, force try/unwrap, naming |
| `security` | Hardcoded secrets, unsafe URLs |
| `accessibility` | Missing labels/hints, color contrast, font sizes |
| `memoryManagement` | Retain cycles, large objects in state |
| `networking` | Missing error handling, synchronous calls |
| `uiPatterns` | Navigation structure, previews, styling consistency |
| `modernization` | Deprecated APIs, legacy concurrency patterns |

### Exit Codes

| Code | Meaning |
|------|---------|
| `0` | No issues at or above the threshold |
| `1` | One or more issues at or above the threshold |
| `2` | Invalid arguments |

### Examples

```bash
# Analyze with defaults
swiftprojectlint /path/to/MyApp

# JSON output, fail only on errors
swiftprojectlint /path/to/MyApp --format json --threshold error

# Analyze only state management and security rules
swiftprojectlint /path/to/MyApp --categories stateManagement security

# Use a custom config file
swiftprojectlint /path/to/MyApp --config ~/configs/strict.yml
```

---

## Configuration File

Place `.swiftprojectlint.yml` in the project root. It is loaded automatically. Pass `--config` to use a different location.

### Full Schema

```yaml
# Disable specific rules entirely.
# Values are the rule's display name (see docs/rules/RULES.md).
# Mutually exclusive with enabled_only; disabled_rules takes precedence if both appear.
disabled_rules:
  - "Print Statement"
  - "Missing Documentation"

# Run only these rules. All others are skipped.
# Mutually exclusive with disabled_rules.
enabled_only:
  - "Force Try"
  - "Force Unwrap"
  - "Hardcoded Secret"

# Exclude file path patterns from all rules.
# Matched against the path relative to the project root.
# Supports: plain substrings, glob patterns (*), and **/ prefix globs.
excluded_paths:
  - "Tests/"
  - "Generated/"
  - "**/*.generated.swift"

# Per-rule overrides: change severity or exclude specific paths for a single rule.
rules:
  "Fat View":
    severity: info                  # error | warning | info

  "Hardcoded Strings":
    severity: warning
    excluded_paths:
      - "Resources/"
      - "Localizable/"

  "Force Try":
    excluded_paths:
      - "LegacyViews/"
```

### Path Matching Rules

| Pattern | Behavior |
|---------|----------|
| `Tests/` | Substring match — excludes any path containing `Tests/` |
| `*.generated.swift` | Glob match against the full relative path |
| `**/*.generated.swift` | Strip `**/`, then glob match against the filename only |

### Opt-In Rules

These rules are **off by default** and must be listed under `enabled_only` to run:

| Rule | Reason |
|------|--------|
| `Magic Layout Number` | High false-positive rate in many codebases |
| `Non-Actor Agent Suffix` | Project-specific naming convention |
| `Hardcoded Strings` | False positives with String Catalogs (`.xcstrings`) — localization keys look like hardcoded text |
| `GeometryReader Overuse` | Sometimes legitimately necessary |
| `onReceive Without Debounce` | Intentional high-frequency updates would false-positive |
| `Missing Dynamic Type Support` | `.lineLimit(1)` is legitimate in many UI designs |
| `Decorative Image Missing Trait` | Determining "decorative" from AST alone is heuristic |
| `String Switch Over Enum` | Operates without full type info; uses structural heuristic |
| `Nested Generic Complexity` | Generic-heavy code is sometimes necessary in frameworks |
| `View Model Direct DB Access` | Many small apps use `@Query` directly per Apple tutorials |
| `Legacy Array Init` | Pure style preference |
| `Legacy Closure Syntax` | Some teams prefer explicit closure types |
| `iOS 17 Observation Migration` | Companion to `legacyObservableObject` for migration planning |

### Precedence

1. `disabled_rules` takes precedence over `enabled_only` if both keys appear (the `enabled_only` key is ignored).
2. CLI `--categories` further restricts whatever the config file produces.
3. Swift Package projects automatically disable `Public in App Target`.
4. Executable targets in Swift Packages automatically exclude `Print Statement` for their source paths.

---

## Inline Suppression

Suppress violations directly in source using structured comments.

### Syntax

```swift
// swiftprojectlint:disable rule-name [rule-name ...]
// swiftprojectlint:enable rule-name [rule-name ...]
// swiftprojectlint:disable:next rule-name [rule-name ...]
// swiftprojectlint:disable:this rule-name [rule-name ...]
```

### Directives

| Directive | Scope |
|-----------|-------|
| `disable` | From this line to the next matching `enable`, or end of file |
| `enable` | Closes a `disable` region opened earlier in the same file |
| `disable:next` | The single line immediately following the comment |
| `disable:this` | The line containing the comment |

### Rule Name Format

Rule names in suppression comments use **kebab-case** derived from the rule's display name:

| Display name | Suppression key |
|---|---|
| `Force Try` | `force-try` |
| `Magic Number` | `magic-number` |
| `Fat View Detection` | `fat-view-detection` |
| `Missing Accessibility Label` | `missing-accessibility-label` |

The general pattern: lowercase the display name and replace spaces with hyphens. Existing hyphens are preserved (e.g. `Non-Actor Agent Suffix` → `non-actor-agent-suffix`).

### Multiple Rules

Space-separate multiple rule names on one directive:

```swift
// swiftprojectlint:disable:next force-try force-unwrap
```

### Suppress All Rules

Omit the rule name to target every rule:

```swift
// swiftprojectlint:disable
// ... suppressed block ...
// swiftprojectlint:enable
```

### Scope

Inline suppression applies **per-file only**. Cross-file issues (e.g. `Related Duplicate State Variable`, which spans multiple files) are not affected by single-file suppression comments.

---

## Rule Reference

See [docs/rules/RULES.md](rules/RULES.md) for the complete list of 145 rules organized by category, with links to per-rule documentation.

Each rule doc includes:
- Display name and identifier
- Category and default severity
- Rationale
- Discussion of detection logic
- Non-violating and violating code examples
