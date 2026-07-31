# SwiftProjectLint User Guide

SwiftProjectLint is a static analysis tool for SwiftUI projects. It uses SwiftSyntax to parse your Swift source files into an abstract syntax tree and then runs specialized visitors across that tree to detect anti-patterns, architectural issues, and code quality problems.

---

## Installation

SwiftProjectLint is distributed as a Swift Package. Clone the repository and build the CLI tool:

```bash
git clone https://github.com/Joseph-Cursio/SwiftProjectLint.git
cd SwiftProjectLint
swift build -c release
```

The compiled binary is at `.build/release/CLI`. Copy it somewhere on your `PATH` or invoke it directly.

---

## Basic Usage

Point the tool at any Swift project directory:

```bash
swiftprojectlint /path/to/MyApp
```

It will recursively find all `.swift` files, analyze them, and print a report to stdout. The exit code is `0` when no issues at or above the threshold are found, non-zero otherwise — making it suitable for CI scripts.

### Running from the Project Root

```bash
cd /path/to/MyApp
swiftprojectlint .
```

---

## Output Formats

### Text (default)

Human-readable output grouped by severity:

```
ExampleView.swift:14 [Warning] Force Try: Avoid force try expressions that can crash at runtime.
  → Use do/catch to handle errors gracefully.
```

### JSON

Machine-readable output for integration with other tools:

```bash
swiftprojectlint /path/to/MyApp --format json
```

```json
[
  {
    "severity": "warning",
    "message": "Force Try: Avoid force try expressions...",
    "filePath": "ExampleView.swift",
    "lineNumber": 14,
    "suggestion": "Use do/catch to handle errors gracefully.",
    "ruleName": "Force Try"
  }
]
```

---

## Filtering by Category

Analyze only specific rule categories using `--categories`:

```bash
swiftprojectlint /path/to/MyApp --categories stateManagement performance
```

Available categories: `stateManagement`, `performance`, `animation`, `architecture`, `codeQuality`, `security`, `accessibility`, `memoryManagement`, `networking`, `uiPatterns`, `modernization`.

---

## Exit Code Threshold

Control the severity that triggers a non-zero exit code:

```bash
# Fail only on errors (default: fail on warnings and above)
swiftprojectlint /path/to/MyApp --threshold error

# Fail on any issue including info
swiftprojectlint /path/to/MyApp --threshold info
```

---

## Configuration File

Place a `.swiftprojectlint.yml` file in your project root to persist configuration. It is loaded automatically. See the [Reference Guide](reference.md) for the full schema.

Quick example:

```yaml
disabled_rules:
  - "Print Statement"
  - "Missing Documentation"

excluded_paths:
  - "Tests/"
  - "Generated/"

rules:
  "Hardcoded Strings":
    severity: info
    excluded_paths:
      - "Resources/"
```

---

## Inline Suppression

Suppress individual violations directly in source code using comments, similar to SwiftLint:

```swift
// swiftprojectlint:disable:next force-try
let data = try! Data(contentsOf: url)

let threshold = 42 // swiftprojectlint:disable:this magic-number

// swiftprojectlint:disable force-try force-unwrap
let a = try! loadConfig()
let b = result!
// swiftprojectlint:enable force-try force-unwrap
```

**Directives:**

| Directive | Effect |
|-----------|--------|
| `// swiftprojectlint:disable rule-name` | Suppress from this line forward |
| `// swiftprojectlint:enable rule-name` | Re-enable a suppressed rule |
| `// swiftprojectlint:disable:next rule-name` | Suppress the next line only |
| `// swiftprojectlint:disable:this rule-name` | Suppress this line only |

Omit the rule name to target all rules. Multiple rule names can appear space-separated on one line. Rule names use kebab-case (e.g. `force-try`, `magic-number`, `fat-view-detection`).

---

## What Gets Skipped Automatically

SwiftProjectLint never analyzes:

- Build output: `.build/`, `DerivedData/`
- Dependencies: `.swiftpm/`, `Pods/`, `Carthage/`
- Version control: `.git/`, `.hg/`, `.svn/`
- Node modules: `node_modules/`
- Nested Swift packages: directories containing their own `Package.swift`
- Generated files: `.pb.swift`, `.generated.swift`, or files whose first five lines contain `DO NOT EDIT` or `Code generated`

---

## macOS App

In addition to the CLI, the project includes a native macOS app (`Sources/App/`) with a SwiftUI interface for interactive analysis. Open the package in Xcode and run the `App` scheme to use it.
