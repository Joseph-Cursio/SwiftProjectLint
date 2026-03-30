import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for all animation-related syntax patterns.
///
/// This class centralizes the registration of all animation patterns by adding them
/// to the `SourcePatternRegistry`. It ensures that all animation-related rules are
/// consistently registered and available for use.
class Animation: BasePatternRegistrar {

    override func registerPatterns() {
        registry.register(registrars: [
            DeprecatedAnimation(),
            AnimationPerformance(),
            WithAnimation(),
            AnimationHierarchy(),
            MatchedGeometry(),
            HardcodedAnimationValues()
        ])
    }
}
