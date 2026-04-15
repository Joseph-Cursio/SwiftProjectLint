import SwiftUI
import Combine
import Core

/// ObservableObject that holds the pattern detection system components.
/// Injected into views via `@EnvironmentObject` for ViewInspector test compatibility.
/// (ViewInspector only supports `@EnvironmentObject` injection, not `@Environment(Type.self)`.)
/// Migration to @Observable is blocked until ViewInspector supports @Environment(Type.self) injection.
@MainActor
// swiftprojectlint:disable:next legacy-observable-object ios17-observation-migration
class SystemComponents: ObservableObject {
    private(set) var visitorRegistry: PatternVisitorRegistry?
    // swiftprojectlint:disable:next legacy-observable-object
    @Published private(set) var patternRegistry: SourcePatternRegistry?
    private(set) var detector: SourcePatternDetector?

    func initialize() async {
        // Task.detached is intentional — escapes @MainActor so registry setup
        // doesn't block the main thread. Task { } would inherit MainActor here.
        // swiftprojectlint:disable:next task-detached
        let system = await Task.detached(priority: .userInitiated) {
            PatternRegistryFactory.createConfiguredSystem()
        }.value

        self.visitorRegistry = system.visitorRegistry
        self.patternRegistry = system.patternRegistry
        self.detector = system.detector
    }
}
