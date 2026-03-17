/// Enum representing known SwiftUI view types for type-safe detection.
public enum SwiftUIViewType: String, CaseIterable, Sendable {
    // Containers
    case vStack = "VStack"
    case hStack = "HStack"
    case zStack = "ZStack"
    case group = "Group"
    case scrollView = "ScrollView"
    case list = "List"
    case section = "Section"
    case form = "Form"

    // Basic display
    case text = "Text"
    case image = "Image"
    case spacer = "Spacer"
    case divider = "Divider"
    case emptyView = "EmptyView"
    case label = "Label"

    // Interactive
    case button = "Button"
    case toggle = "Toggle"
    case slider = "Slider"
    case stepper = "Stepper"
    case picker = "Picker"
    case datePicker = "DatePicker"
    case colorPicker = "ColorPicker"
    case textField = "TextField"
    case secureField = "SecureField"

    // Lazy layout
    case lazyVStack = "LazyVStack"
    case lazyHStack = "LazyHStack"
    case lazyZStack = "LazyZStack"
    case grid = "Grid"
    case table = "Table"
    case outlineGroup = "OutlineGroup"
    case disclosureGroup = "DisclosureGroup"

    // Display
    case progressView = "ProgressView"
    case gauge = "Gauge"
    case chart = "Chart"
    case canvas = "Canvas"
    case timelineView = "TimelineView"

    // Navigation & presentation
    case navigationView = "NavigationView"
    case navigationLink = "NavigationLink"
    case tabView = "TabView"
    case videoPlayer = "VideoPlayer"
    case map = "Map"
    case forEach = "ForEach"

    // Other
    case color = "Color"
}

public extension SwiftUIViewType {
    /// Container views that hold child views in a layout.
    static let containerViews: Set<SwiftUIViewType> = [
        .vStack, .hStack, .zStack, .group, .scrollView, .list, .section, .form
    ]

    /// Built-in system views that are not custom user-defined views.
    static let systemViews: Set<SwiftUIViewType> = [
        // Basic display
        .text, .image, .spacer, .divider, .emptyView, .label,
        // Interactive
        .button, .toggle, .slider, .stepper, .picker, .datePicker, .colorPicker,
        .textField, .secureField,
        // Lazy layout
        .lazyVStack, .lazyHStack, .lazyZStack, .grid, .table, .outlineGroup, .disclosureGroup,
        // Display
        .progressView, .gauge, .chart, .canvas, .timelineView,
        // Navigation & presentation
        .navigationView, .tabView, .videoPlayer, .map
    ]
}
