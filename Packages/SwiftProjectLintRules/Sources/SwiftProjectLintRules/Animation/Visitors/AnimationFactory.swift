/// The SwiftUI `Animation` factory methods, in one place.
///
/// Two Animation rules ask the same question — "is this call an animation factory?" —
/// and each used to answer it from its own literal set. They had already drifted:
/// `AnimationPerformanceVisitor` listed five and `HardcodedAnimationValuesVisitor` seven,
/// so the performance rule silently ignored every `.interactiveSpring(…)` and
/// `.interpolatingSpring(…)` in the codebases it ran on. Found by dogfooding
/// `ParallelListDrift` on this project.
///
/// One list means a factory added for one rule is honoured by the other.
enum AnimationFactory {

    /// Factory methods on `Animation` that take timing parameters.
    static let all: Set<String> = [
        "easeIn", "easeOut", "easeInOut", "linear",
        "spring", "interactiveSpring", "interpolatingSpring"
    ]

    /// Whether `name` is one of the factories.
    static func matches(_ name: String) -> Bool {
        all.contains(name)
    }
}
