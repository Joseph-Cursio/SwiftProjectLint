/// The SwiftUI views that carry their own action, in one place.
///
/// Two accessibility rules ask the same question — "does this view already respond to the
/// user?" — and each answered it from its own literal set. They had drifted in both
/// directions: `IsButtonTraitWithoutActionVisitor` knew `Picker` and not `Slider`,
/// `TapTargetTooSmallVisitor` knew `Slider` and not `Picker`. Each omission is a real miss:
/// a `Slider` carrying a redundant `.isButton` trait was reported as unactionable, and a
/// `Picker` squeezed below 44pt was not reported at all.
///
/// One list means a view added for one rule is honoured by the other. Found by dogfooding
/// `ParallelListDrift` on this project, the same way `AnimationFactory` was.
enum InteractiveView {

    /// Views that respond to the activate gesture without any modifier being added.
    static let all: Set<String> = [
        "Button", "NavigationLink", "Link", "Menu",
        "Toggle", "Stepper", "Picker", "Slider"
    ]

    /// Whether `name` is one of the interactive views.
    static func matches(_ name: String) -> Bool {
        all.contains(name)
    }
}
