# LintStudioUI Shared Components

LintStudioUI (`~/xcode_projects/LintStudioUI`) is a shared Swift package with two library products used by both SwiftLintRuleStudio and SwiftProjectLint.

## Package Structure

### LintStudioCore (pure logic, no SwiftUI)

| Directory | Components | Purpose |
|-----------|-----------|---------|
| `Protocols/` | LintSeverity, LintCategory, LintViolation, LintRule | Generic interfaces for lint data types |
| `DiffEngine/` | UnifiedDiffEngine, DiffLine, DiffSpan | LCS-based unified diff with character-level highlighting |
| `Export/` | HTMLEscaping, CSVEscaping, HTMLReportTemplate | Shared export utilities for HTML/CSV reports |
| `FileIO/` | SafeFileWriter, YAMLCommentPreserver | Atomic writes with backups, YAML comment round-tripping |

### LintStudioUI (SwiftUI components)

| Directory | Components | Purpose |
|-----------|-----------|---------|
| `Badges/` | SeverityBadge\<S\>, CategoryBadge\<C\>, StatisticBadge | Colored label badges for severity, category, and stats |
| `Cards/` | SummaryCard | Bordered card with title, count, subtitle |
| `Headers/` | GroupHeader | Section header with count and proportional bar |
| `CodeDisplay/` | CodeBlock, UnifiedDiffContentView, DiffLineView, DiffLine+Color | Code snippets and GitHub-style diff rendering |
| `Export/` | ExportFormat | Enum (HTML/JSON/CSV) with metadata |

## Usage Scorecard

| Component | SwiftLintRuleStudio | SwiftProjectLint |
|-----------|:-------------------:|:----------------:|
| **LintStudioCore** | | |
| SafeFileWriter | Yes | Yes |
| YAMLCommentPreserver | Yes | Yes |
| HTMLEscaping | Yes | Yes |
| CSVEscaping | Yes | Yes |
| HTMLReportTemplate | Yes | Yes |
| UnifiedDiffEngine | Yes (via views) | Yes (via views) |
| DiffLine / DiffSpan | Yes (via views) | Yes (via views) |
| LintSeverity | Yes | Yes |
| LintCategory | Yes | Yes |
| LintViolation | Yes | Yes |
| LintRule | Yes | No |
| **LintStudioUI** | | |
| SeverityBadge | Yes | No |
| CategoryBadge | Yes | No |
| StatisticBadge | Yes | Yes |
| SummaryCard | Yes | No |
| GroupHeader | Yes | No |
| CodeBlock | Yes | No |
| UnifiedDiffContentView | Yes | Yes |
| DiffLineView | Yes (via content view) | Yes (via content view) |
| DiffLine+Color | Yes (via content view) | Yes (via content view) |
| ExportFormat | Yes | No |

## Why Some Components Are Not Used by SwiftProjectLint

SwiftProjectLint has a simpler UI than SwiftLintRuleStudio:

- **SeverityBadge** -- `LintIssueRow` uses its own severity icons (SF Symbols with red/orange/blue) rather than text badges. The 3-tier severity (error/warning/info) needs icon-based display, not text labels.
- **CategoryBadge** -- The app doesn't show rule categories in the issue list UI.
- **SummaryCard** -- Uses `StatisticBadge` instead (simpler stacked label/value layout without bordered card chrome).
- **GroupHeader** -- Issues aren't grouped with proportional bars; they're displayed in a flat list.
- **CodeBlock** -- No code snippet display in issue details.
- **ExportFormat** -- The CLI has its own `OutputFormat` enum tied to `ArgumentParser`'s `ExpressibleByArgument`. The app doesn't yet offer export from the GUI.
- **LintRule** -- Rules use `DetectionPattern`/`RuleIdentifier` which haven't been conformed to the protocol yet.

## Conformance Bridge Files

Each app maps its domain types to LintStudioCore protocols via retroactive conformances:

### SwiftLintRuleStudio (`App/LintStudioConformances.swift`)

| App Type | Protocol | Notes |
|----------|----------|-------|
| `Severity` | `LintSeverity` | `isError` = (.error), `isInfo` = false (default) |
| `RuleCategory` | `LintCategory` | 5 cases; `RuleCategoryColors` maps to SwiftUI colors |
| `Violation` | `LintViolation` | `ruleIdentifier` = ruleID, `filePath`/`message` already match |
| `Rule` | `LintRule` | `identifier` = id, `ruleDescription` = description |

### SwiftProjectLint (`Sources/App/Models/LintStudioConformances.swift`)

| App Type | Protocol | Notes |
|----------|----------|-------|
| `IssueSeverity` | `LintSeverity` | 3-tier: `isError` = (.error), `isInfo` = (.info) |
| `PatternCategory` | `LintCategory` | 12 cases; `PatternCategoryColors` maps to SwiftUI colors |
| `LintIssue` | `LintViolation` | `line` from first location, `column` = nil |

## Dependency Graph

```
LintStudioUI package
  +-- LintStudioCore (no UI dependency)
  +-- LintStudioUI (depends on LintStudioCore)

SwiftLintRuleStudio
  +-- SwiftLintRuleStudioCore --> LintStudioCore (SafeFileWriter, YAMLCommentPreserver)
  +-- App target --> LintStudioCore + LintStudioUI (all shared components)

SwiftProjectLint
  +-- Core target --> LintStudioCore (re-exported; export formatters use HTMLEscaping etc.)
  +-- App target --> LintStudioUI (StatisticBadge, UnifiedDiffContentView)
  +-- CLI target --> Core (gets LintStudioCore transitively)
```

## Adoption Path for Unused Components

When adding features to SwiftProjectLint, prefer shared components over building new ones:

- **Issue grouping by file/rule** -- Use `GroupHeader` for proportional bar headers
- **Category display in issue rows** -- Use `CategoryBadge<PatternCategory>` with `PatternCategoryColors`
- **Severity badges** -- Use `SeverityBadge<IssueSeverity>` if switching from icons to text labels
- **Summary cards** -- Use `SummaryCard` for richer dashboard-style summary sections
- **Code snippets** -- Use `CodeBlock` if adding source code display to issue details
- **App-side export** -- Use `ExportFormat` and the formatters in `Core/Export/` for GUI export
- **Rule protocol** -- Conform `DetectionPattern` or `RuleIdentifier` to `LintRule` for generic rule browsing views
