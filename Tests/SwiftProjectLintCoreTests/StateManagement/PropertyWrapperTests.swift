import Testing
import SwiftProjectLintCore

struct PropertyWrapperTests {
    
    @Test func testAllPropertyWrappersAreDefined() {
        let allWrappers = PropertyWrapper.allCases
        #expect(!allWrappers.isEmpty)
        
        // Verify common SwiftUI property wrappers exist
        #expect(allWrappers.contains(.state))
        #expect(allWrappers.contains(.stateObject))
        #expect(allWrappers.contains(.observedObject))
        #expect(allWrappers.contains(.environmentObject))
        #expect(allWrappers.contains(.binding))
        #expect(allWrappers.contains(.environment))
    }
    
    @Test func testPropertyWrapperRawValues() {
        #expect(PropertyWrapper.state.rawValue == "State")
        #expect(PropertyWrapper.stateObject.rawValue == "StateObject")
        #expect(PropertyWrapper.observedObject.rawValue == "ObservedObject")
        #expect(PropertyWrapper.environmentObject.rawValue == "EnvironmentObject")
        #expect(PropertyWrapper.binding.rawValue == "Binding")
        #expect(PropertyWrapper.environment.rawValue == "Environment")
        #expect(PropertyWrapper.focusState.rawValue == "FocusState")
        #expect(PropertyWrapper.gestureState.rawValue == "GestureState")
        #expect(PropertyWrapper.unknown.rawValue == "Unknown")
    }
    
    @Test func testAllCasesCompleteness() {
        // Verify all expected property wrappers are included
        let expectedWrappers: Set<String> = [
            "State", "StateObject", "ObservedObject", "EnvironmentObject",
            "Binding", "Environment", "FocusState", "GestureState",
            "ScaledMetric", "Namespace", "FetchRequest", "SectionedFetchRequest",
            "Query", "AppStorage", "SceneStorage", "UIApplicationDelegateAdaptor",
            "WKExtensionDelegateAdaptor", "NSApplicationDelegateAdaptor",
            "FocusedBinding", "FocusedValue", "AccessibilityFocusState", "Unknown"
        ]
        
        let actualWrappers = Set(PropertyWrapper.allCases.map { $0.rawValue })
        #expect(actualWrappers == expectedWrappers)
    }
    
    @Test func testPropertyWrapperEquality() {
        let state1 = PropertyWrapper.state
        let state2 = PropertyWrapper.state
        let stateObject = PropertyWrapper.stateObject
        
        #expect(state1 == state2)
        #expect(state1 != stateObject)
    }
}
