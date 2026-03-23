import SwiftUI
import Combine
import Core

/// ObservableObject that holds the pattern detection system components.
/// Injected into views via `@EnvironmentObject` for ViewInspector test compatibility.
/// (ViewInspector only supports `@EnvironmentObject` injection, not `@Environment(Type.self)`.)
@MainActor
class SystemComponents: ObservableObject {
    private(set) var visitorRegistry: PatternVisitorRegistry?
    @Published private(set) var patternRegistry: SourcePatternRegistry?
    private(set) var detector: SourcePatternDetector?

    func initialize() async {
        // Offload heavy registry setup from the main actor
        let system = await Task.detached(priority: .userInitiated) {
            PatternRegistryFactory.createConfiguredSystem()
        }.value

        self.visitorRegistry = system.visitorRegistry
        self.patternRegistry = system.patternRegistry
        self.detector = system.detector
    }
}
