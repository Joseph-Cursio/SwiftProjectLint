import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

/// Tests for different property wrapper types detection
@Suite
struct StateVariableVisitorPropertyWrapperTests {

    struct WrapperCase: CustomTestStringConvertible, Sendable {
        let declaration: String
        let expectedWrapper: PropertyWrapper
        let expectedName: String?
        let expectedType: String?
        var testDescription: String { "@\(expectedWrapper.rawValue)" }

        init(_ declaration: String, wrapper: PropertyWrapper, name: String? = nil, type: String? = nil) {
            self.declaration = declaration
            self.expectedWrapper = wrapper
            self.expectedName = name
            self.expectedType = type
        }
    }

    nonisolated static let cases: [WrapperCase] = [
        WrapperCase("@StateObject private var viewModel = ViewModel()", wrapper: .stateObject, name: "viewModel"),
        WrapperCase("@ObservedObject var viewModel: ViewModel", wrapper: .observedObject, type: "ViewModel"),
        WrapperCase("@EnvironmentObject var settings: AppSettings", wrapper: .environmentObject, name: "settings"),
        WrapperCase("@Binding var isEnabled: Bool", wrapper: .binding, type: "Bool"),
        WrapperCase("@Environment(\\.colorScheme) var colorScheme", wrapper: .environment, name: "colorScheme"),
        WrapperCase("@FocusState private var isFocused: Bool", wrapper: .focusState, name: "isFocused"),
        WrapperCase("@AppStorage(\"username\") var username: String = \"\"", wrapper: .appStorage, type: "String"),
        WrapperCase("@SceneStorage(\"draft\") var draft: String = \"\"", wrapper: .sceneStorage),
        WrapperCase("@GestureState private var dragOffset = CGSize.zero", wrapper: .gestureState),
        WrapperCase("@Namespace private var animation", wrapper: .namespace),
        WrapperCase("@ScaledMetric var size: CGFloat = 100", wrapper: .scaledMetric)
    ]

    @Test(arguments: cases)
    func detectsWrapper(_ testCase: WrapperCase) throws {
        let source = """
        struct TestView: View {
            \(testCase.declaration)
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVar = try #require(visitor.stateVariables.first)
        #expect(stateVar.propertyWrapper == testCase.expectedWrapper)

        if let expectedName = testCase.expectedName {
            #expect(stateVar.name == expectedName)
        }
        if let expectedType = testCase.expectedType {
            #expect(stateVar.type == expectedType)
        }
    }

    @Test
    func multiplePropertyWrapperTypes() throws {
        let source = """
        struct TestView: View {
            @State private var count = 0
            @StateObject private var viewModel = ViewModel()
            @ObservedObject var data: DataModel
            @EnvironmentObject var settings: AppSettings
            @Binding var isEnabled: Bool
            var body: some View { Text("Test") }
        }
        """

        let visitor = createVisitor(for: source)
        let stateVars = visitor.stateVariables

        #expect(stateVars.count == 5)
        #expect(stateVars.contains { $0.propertyWrapper == .state })
        #expect(stateVars.contains { $0.propertyWrapper == .stateObject })
        #expect(stateVars.contains { $0.propertyWrapper == .observedObject })
        #expect(stateVars.contains { $0.propertyWrapper == .environmentObject })
        #expect(stateVars.contains { $0.propertyWrapper == .binding })
    }

    // MARK: - Helper Methods

    private func createVisitor(for source: String) -> StateVariableVisitor {
        let syntax = Parser.parse(source: source)
        let visitor = StateVariableVisitor(
            viewName: "TestView",
            filePath: "/test/TestView.swift",
            sourceContents: source
        )
        visitor.walk(syntax)
        return visitor
    }
}
