import SwiftUI

/// `ParentView` is a SwiftUI view that acts as a container for its child views and manages UI state.
/// 
/// - Displays a title "Parent View" at the top.
/// - Shows a `ProgressView` while loading; otherwise greets the user by name.
/// - Provides a segmented picker with two tabs to switch between modes.
/// - Embeds a `ChildView` for showing additional content.
/// - State variables:
///   - `isLoading`: Toggles between loading state and content.
///   - `userName`: Stores the currently displayed user's name.
///   - `selectedTab`: Tracks the selected segment in the picker.
/// - All contents are vertically stacked and padded.
/// - Designed for demonstration or composition purposes in SwiftUI.
struct ParentView: View {
    @State private var isLoading = false
    @State private var userName = ""
    @State private var selectedTab = 0
    
    var body: some View {
        VStack {
            Text("Parent View")
                .font(.title)
            
            if isLoading {
                ProgressView()
            } else {
                Text("Hello, \(userName)")
            }
            
            Picker("Tab", selection: $selectedTab) {
                Text("Tab 1").tag(0)
                Text("Tab 2").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            
            ChildView()
        }
        .padding()
    }
}

#Preview {
    ParentView()
} 
