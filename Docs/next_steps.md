# Next Steps for SwiftProjectLint

**Last Updated:** March 2026

---

## Immediate / In-Progress (from PRD "Implementation Roadmap")

1. **Refactoring** — ContentView and LintResultsView need to be broken into smaller components; dependency injection improvements
2. **Type-safe detection** — Property wrapper and view type logic still partially uses string comparisons (migration in progress)
3. **Async/await conversion** — Incomplete; file I/O, analysis operations need to move off main thread
4. **AST caching** — Not yet implemented
5. **Test coverage** — Target is >80%; recent commits have been improving this but more to do (edge cases in PatternDetector, AdvancedAnalyzer, expanded UI tests)

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

The most actionable near-term work is: finishing the type-safe migration, async/await conversion, AST caching, and building toward a CLI mode for CI/CD — those are the foundation for the bigger features like Xcode integration and auto-fix.
