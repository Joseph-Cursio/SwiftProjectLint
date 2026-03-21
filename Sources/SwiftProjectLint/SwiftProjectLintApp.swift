//
//  SwiftProjectLintApp.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/1/25.
//

import SwiftUI
import Combine
import SwiftProjectLintCore

/// The main entry point for the SwiftProjectLint application.
///
/// `SwiftProjectLintApp` is the root structure conforming to the `App` protocol,
/// responsible for initializing the app's window group and setting up the initial view hierarchy.
///
/// The app's lifecycle is managed by SwiftUI, and the root view presented to the user is `ContentView`.
/// The app also initializes the SwiftSyntax pattern registry for advanced code analysis.
///
/// - Note: The `@main` attribute designates this struct as the application's entry point.
/// - SeeAlso: `ContentView`
@main
struct SwiftProjectLintApp: App {

    // Global system components - these will be injected into views that need them
    @StateObject private var systemComponents = SystemComponents()

    init() {
        if CommandLine.arguments.contains("--reset-userdefaults") {
            if let appDomain = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: appDomain)
                // Note: UserDefaults reset may show INVALID_PERSONA warnings - this is normal in test environments
                print(
                    "Note: UserDefaults reset may show INVALID_PERSONA " +
                    "warnings - this is normal in test environments"
                )
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(systemComponents)
                .task {
                    // Initialize system components after the view hierarchy is set up
                    if systemComponents.patternRegistry == nil {
                        await systemComponents.initialize()
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)
    }
}

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
