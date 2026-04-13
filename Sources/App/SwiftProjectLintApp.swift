//
//  SwiftProjectLintApp.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/1/25.
//

import SwiftUI
import Combine
import Core

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

    // SystemComponents uses ObservableObject intentionally — ViewInspector requires
    // @EnvironmentObject injection and does not support @Environment(Type.self) for
    // @Observable types. Migration is blocked until ViewInspector adds that support.
    // swiftprojectlint:disable:next legacy-observable-object ios17-observation-migration
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
                    // SPM-built executables launch as background processes.
                    // Activate as a regular foreground app so keyboard input works.
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)

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
