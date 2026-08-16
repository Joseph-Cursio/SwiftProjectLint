import SwiftEffectInference

/// Thin forwarder onto the framework gate tables in the shared leaf.
///
/// The tables moved to `SwiftEffectInference.FrameworkGates` with the inferrer
/// that reads them. Before the move the two files were **byte-identical** once
/// the type name was normalised — 505 lines maintained twice, which is the
/// clearest instance of the duplication the shared leaf exists to remove.
///
/// ## Why the gates exist
///
/// A name match alone produced a real false positive: a user-defined
/// `class Counter` in a module with no `import Metrics` classified as
/// observational purely on the name. Requiring the framework's import before a
/// framework-specific name means anything to the classifier is what fixed it.
///
/// Only the members SwiftProjectLint actually names are forwarded. The rest of
/// the table is consumed by the inferrer, which now reads it directly from the
/// leaf — forwarding the whole surface would rebuild the duplication in a
/// thinner form.
public enum FrameworkAllowlist {

    /// Frameworks whose gate fires without requiring a matching import, because
    /// the construct is a language feature rather than a package.
    public static var alwaysActiveFrameworks: Set<String> {
        FrameworkGates.alwaysActiveFrameworks
    }

    /// Structured concurrency's gate name.
    public static var swiftConcurrency: String {
        FrameworkGates.swiftConcurrency
    }

    /// The phrase naming *why* a framework's read verbs are idempotent, for
    /// diagnostic prose. Table-driven upstream, so adding a framework does not
    /// require touching the inferrer.
    public static func idempotentMethodPhrasing(forFramework framework: String) -> String {
        FrameworkGates.idempotentMethodPhrasing(forFramework: framework)
    }
}
