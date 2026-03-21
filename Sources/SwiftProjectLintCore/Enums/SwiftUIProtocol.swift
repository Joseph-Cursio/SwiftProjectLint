/// Enum representing known SwiftUI protocols for type-safe detection.
public enum SwiftUIProtocol: String, CaseIterable, Sendable {
    case app = "App"
    case view = "View"
    case observableObject = "ObservableObject"
    case previewProvider = "PreviewProvider"
}
