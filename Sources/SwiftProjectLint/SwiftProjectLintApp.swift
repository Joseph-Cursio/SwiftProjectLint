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
                do {
                    UserDefaults.standard.removePersistentDomain(forName: appDomain)
                } catch {
                    // Log but don't fail - persona warnings are expected in UI test environment
                    print("Note: UserDefaults reset may show INVALID_PERSONA warnings - this is normal in test environments")
                }
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(systemComponents)
                .onAppear {
                    // Initialize system components after the view hierarchy is set up
                    if systemComponents.patternRegistry == nil {
                        systemComponents.initialize()
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)
    }
}


/// ObservableObject that holds the pattern detection system components.
/// This replaces the singleton pattern with dependency injection.
@MainActor
class SystemComponents: ObservableObject {
    private(set) var visitorRegistry: PatternVisitorRegistry!
    private(set) var patternRegistry: SourcePatternRegistry!
    private(set) var detector: SourcePatternDetector!
    
    func initialize() {
        print("DEBUG: SystemComponents.initialize() called")
        let (visitorRegistry, patternRegistry, detector) = PatternRegistryFactory.createConfiguredSystem()
        print("DEBUG: Pattern registry created, checking patterns...")
        
        // Check if patterns were registered
        let allPatterns = patternRegistry.getAllPatterns()
        print("DEBUG: Total patterns registered: \(allPatterns.count)")
        
        for category in PatternCategory.allCases {
            let patterns = patternRegistry.getPatterns(for: category)
            print("DEBUG: Category \(category) has \(patterns.count) patterns")
        }
        
        self.visitorRegistry = visitorRegistry
        self.patternRegistry = patternRegistry
        self.detector = detector
        print("DEBUG: SystemComponents initialization complete")
    }
}
