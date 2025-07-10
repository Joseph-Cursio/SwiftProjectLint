import Foundation

/// Enum representing supported SwiftUI property wrappers for state management.
public enum PropertyWrapper: String, CaseIterable {
    case state = "State"
    case stateObject = "StateObject"
    case observedObject = "ObservedObject"
    case environmentObject = "EnvironmentObject"
    case binding = "Binding"
    case environment = "Environment"
    case focusState = "FocusState"
    case gestureState = "GestureState"
    case scaledMetric = "ScaledMetric"
    case namespace = "Namespace"
    case fetchRequest = "FetchRequest"
    case sectionedFetchRequest = "SectionedFetchRequest"
    case query = "Query"
    case appStorage = "AppStorage"
    case sceneStorage = "SceneStorage"
    case uiApplicationDelegateAdaptor = "UIApplicationDelegateAdaptor"
    case wkExtensionDelegateAdaptor = "WKExtensionDelegateAdaptor"
    case nsApplicationDelegateAdaptor = "NSApplicationDelegateAdaptor"
    case focusedBinding = "FocusedBinding"
    case focusedValue = "FocusedValue"
    case accessibilityFocusState = "AccessibilityFocusState"
    case unknown = "Unknown"
}

public extension PropertyWrapper {
    /// Returns the full representation of the property wrapper (e.g., "@State").
    var fullRepresentation: String {
        return "@\(self.rawValue)"
    }
} 