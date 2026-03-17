# Next Steps for SwiftProjectLint

**Last Updated:** March 2026

---

## Immediate / In-Progress (from PRD "Implementation Roadmap")

1. ~~**Type-safe detection**~~ — **Done.** `SwiftUIViewType` enum, `SwiftUIProtocol` enum, and shared `isSwiftUIView` helper replace all scattered string comparisons for view types, protocols, and property wrappers
2. **Async/await conversion** — Incomplete; file I/O, analysis operations need to move off main thread
3. **AST caching** — Not yet implemented
4. **Test coverage** — 678 tests across 134 suites. Recent additions include ContentViewModel unit tests (17) and IssueSummarySection ViewInspector tests (5). Remaining gaps: edge cases in PatternDetector, AdvancedAnalyzer, and integration tests for the full analysis pipeline

---

## High Priority Future Features (PRD targets Q2-Q3 2026)

6. **Xcode Source Editor Extension** — Inline annotations, quick fixes, live analysis
7. **Auto-fix capabilities** — Automated refactoring via SwiftSyntax
8. **CI/CD integration** — CLI mode, JSON/XML output, GitHub Actions, exit codes
9. **Incremental analysis** — File watcher, only re-analyze changed files
10. **SwiftUI Preview integration** — Live issue overlay

---

## Medium Priority (Q4 2026 - Q2 2027)

11. **Custom rule engine** — Config files, plugin system, team rule sets
12. **Dependency graph visualization** — Interactive view hierarchy graphs, exportable diagrams
13. **Performance profiling** — Static analysis, trend tracking, regression detection
14. **Enhanced accessibility analysis** — Color contrast, VoiceOver simulation, Dynamic Type
15. **Advanced reporting** — HTML/Markdown reports, historical trends

---

## New Pattern Categories (from recommendations doc)

The recommendations doc suggests ~10 new visitor classes and 7 new pattern categories: State Flow, Memory, Navigation, Testing, Environment, Compatibility, and Custom Modifier patterns. High-priority picks are:

- SwiftUI Animation Analyzer (partially done)
- State Flow Analyzer
- Memory Pressure Detector
- Navigation Complexity Analyzer
- Accessibility Completeness Checker

---

## Technical Debt (from refactoring_ideas.md)

- Dead code cleanup
- Centralized shared utilities
- Consistent error handling with `Result<T, Error>`
- Better modularization / public API surface
- Documentation (API docs, developer onboarding guide)

---

## Recommended Starting Point

The most actionable near-term work is: async/await conversion, AST caching, and building toward a CLI mode for CI/CD — those are the foundation for the bigger features like Xcode integration and auto-fix.
