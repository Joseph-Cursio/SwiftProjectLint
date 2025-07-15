import SwiftUI

/// A SwiftUI view that displays child-specific content and state.
///
/// `ChildView` is designed to be used as a part of a parent-child view hierarchy, potentially duplicating
/// some state from `ParentView`. It manages its own loading state, user name, and child-specific data.
/// 
/// The view presents:
/// - A title indicating it is the child view.
/// - A `ProgressView` if loading is active, or the child-specific data otherwise.
/// - A `TextField` for editing the child-specific data.
/// - The current user name, which may be shared with or duplicated from a parent view.
/// 
/// > Note: `isLoading` and `userName` are marked as duplicating state from `ParentView`, suggesting
///   a possible opportunity to refactor these properties to use shared or observable state if needed.
///
/// # Preview
/// A preview of the child view is provided using the `#Preview` macro.
struct ChildView: View {
    @State private var isLoading = false  // Duplicate of ParentView
    @State private var userName = ""      // Duplicate of ParentView
    @State private var childSpecificData = ""
    
    var body: some View {
        VStack {
            Text("Child View")
                .font(.title2)
            
            if isLoading {
                ProgressView("Loading child data...")
            } else {
                Text("Child data: \(childSpecificData)")
            }
            
            TextField("Child specific data", text: $childSpecificData)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Text("User: \(userName)")
        }
        .padding()
    }
}
