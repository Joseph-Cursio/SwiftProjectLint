import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Enum representing supported SwiftUI property wrappers for state management.
public enum PropertyWrapper: String, CaseIterable, Sendable {
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

    /// Attribute names whose presence marks a stored property as SwiftUI/Combine
    /// state, so coupling rules (direct-instantiation, concrete-type-usage) skip
    /// it — e.g. `@StateObject var model = Model()` is the standard pattern, not a
    /// DI smell. Sourced from the typed cases so a raw-value rename stays in sync;
    /// `Published` is Combine's wrapper (no SwiftUI-state enum case of its own) and
    /// is listed explicitly.
    public static let stateStorageAttributeNames: Set<String> = {
        let cases: [Self] = [
            .state, .stateObject, .observedObject, .environmentObject,
            .binding, .appStorage, .sceneStorage
        ]
        return Set(cases.map(\.rawValue)).union(["Published"])
    }()
}
