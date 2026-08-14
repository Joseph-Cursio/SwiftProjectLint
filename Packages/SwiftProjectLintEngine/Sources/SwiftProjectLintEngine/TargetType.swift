/// Whether the analyzed code is an app target, a library, or should be detected
/// from the project structure.
///
/// A handful of rules assume the single-target app model — `publicInAppTarget` is
/// the clearest case: in an app, a `public` declaration is over-exposure, because
/// nothing outside the target can consume it; in a library, `public` *is* the API.
/// The same declaration is a finding in one and the point of the code in the other.
///
/// Detection alone cannot always settle which applies. `auto` looks for a
/// `Package.swift`, which answers correctly for a Swift package linted at its root
/// and says "app" for everything else — including a framework target in an Xcode
/// project, and including a package linted from a subdirectory. Those are libraries
/// that do not look like one from the path handed to the linter, and no amount of
/// sniffing settles it from inside the analyzed directory. This enum exists so the
/// caller can state the answer instead.
public enum TargetType: Sendable {
    /// Detect from project structure: a directory containing `Package.swift` is a
    /// library, anything else is an app target.
    case auto

    /// Treat as an app target, enforcing rules like `publicInAppTarget` even when a
    /// `Package.swift` is present.
    case app

    /// Treat as a library, suppressing rules that assume a single-target app
    /// regardless of whether a `Package.swift` was found.
    case library
}
