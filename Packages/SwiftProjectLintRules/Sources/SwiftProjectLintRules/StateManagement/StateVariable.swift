import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// Represents a state-related property declared within a SwiftUI view.
///
/// `StateVariable` encapsulates information about a property that uses a SwiftUI property wrapper
/// such as `@State`, `@StateObject`, `@ObservedObject`, or `@EnvironmentObject`. This structure is
/// used for static analysis of SwiftUI projects to track how state is managed and propagated across views.
///
/// - Parameters:
///   - name: The name of the state variable as declared in the source code.
///   - type: The declared type of the state variable (e.g., `Bool`, `String`, `MyModel`, etc.).
///   - filePath: The absolute or relative path to the file where the state variable is declared.
///   - lineNumber: The 1-based line number in the file where the state variable appears.
///   - viewName: The name of the containing SwiftUI view (typically the struct name, inferred from the file name).
///   - propertyWrapper: The property wrapper used (e.g., `@State`, `@StateObject`, `@ObservedObject`, or `@EnvironmentObject`).
///
public struct StateVariable: Sendable {
    public let name: String
    public let type: String
    public let filePath: String
    public let lineNumber: Int
    public let viewName: String
    public let propertyWrapper: PropertyWrapper
} 
