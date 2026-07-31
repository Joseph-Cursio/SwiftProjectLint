import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the Animation Without Reduce Motion pattern.
///
/// Provides the pattern for detecting SwiftUI views that animate without ever
/// consulting the user's Reduce Motion preference. Opt-in.
struct AnimationWithoutReduceMotion: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .animationWithoutReduceMotion,
            visitor: AnimationWithoutReduceMotionVisitor.self,
            severity: .info,
            category: .accessibility,
            messageTemplate: "View animates without checking accessibilityReduceMotion",
            suggestion: "Read @Environment(\\.accessibilityReduceMotion) and use it to soften "
                + "the motion, e.g. .animation(reduceMotion ? nil : .easeInOut, value:).",
            description: "Detects SwiftUI views that animate but never consult the user's "
                + "Reduce Motion preference. Opt-in — enable via enabled_only."
        )
    }
}
