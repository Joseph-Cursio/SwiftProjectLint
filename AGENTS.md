# Agent Instructions for Swift Project

## Environment Setup
- This project uses Swift 5.9+.
- If Swift is not installed, use `sudo apt-get update && sudo apt-get install swift`.
- The project relies on Swift Package Manager (SPM).

## Development Workflow
- **Building:** Always run `swift build` after making changes to ensure syntax validity.
- **Testing:** Run `swift test` to verify logic. Do not skip tests.
- **Dependencies:** If adding a dependency, modify `Package.swift` and run `swift package resolve`.

## Constraints & Style
- **Linux Compatibility:** Avoid using `UIKit`, `AppKit`, or macOS-only APIs.
- **Concurrency:** Prefer `async/await` over completion handlers.
- **Documentation:** Use Triple-slash `///` comments for all public functions.