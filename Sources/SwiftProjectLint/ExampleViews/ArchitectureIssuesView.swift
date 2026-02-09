import SwiftUI
import Combine

// Architecture Issue: Missing protocol
/// `UserManager` is an observable object responsible for handling user-related operations,
/// such as fetching and managing the current user's data.
/// 
/// - Properties:
///   - currentUser: The currently authenticated user, if any.
///   - isLoading: A Boolean indicating whether a user fetch operation is in progress.
///
/// - Methods:
///   - fetchUser(): Initiates a simulated asynchronous fetch to load user information. Updates
///     `currentUser` and `isLoading` accordingly when the operation completes.
///
/// `UserManager` is intended to be used with SwiftUI views as a source of truth for user data.
@MainActor
class UserManager: ObservableObject {
    @Published var currentUser: User?
    @Published var isLoading = false
    
    func fetchUser() {
        isLoading = true
        // Simulate network call
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Task { @MainActor in
                self.currentUser = User(name: "John Doe", email: "john@example.com")
                self.isLoading = false
            }
        }
    }
}

/// `User` is a simple data structure representing a user's basic information.
///
/// - Properties:
///   - name: The full name of the user.
///   - email: The email address associated with the user.
///
/// `User` is typically used for demonstration purposes or as a lightweight
/// model for user-related features in the UI.
struct User {
    let name: String
    let email: String
}

// Architecture Issue: Fat view with too many state variables
/// `ArchitectureIssuesView` is a SwiftUI view intended to demonstrate and highlight several common architectural, code quality, and UI issues.
/// 
/// - State Properties:
///   - `isLoading`: Indicates if a loading operation is in progress.
///   - `userName`: Holds the current value of the user's name input.
///   - `userEmail`: Holds the current value of the user's email input.
///   - `selectedTab`: Tracks the currently selected tab index.
///   - `showAlert`: Controls the presentation of an alert.
///   - `alertMessage`: Stores the message displayed in the alert.
///   - `isEditing`: Indicates whether the view is in editing mode.
///   - `searchText`: Holds the value of the current search input.
///   - `sortOrder`: Represents the selected sort order (`ascending` or `descending`).
///   - `filterType`: Represents the selected filter type (`all`, `active`, or `inactive`).
///   - `userManager`: An observable object managing user-related data and actions.
/// 
/// - Issues Demonstrated:
///   - Architecture Issues:
///     - Fat view with numerous state variables.
///     - Missing dependency injection for observable objects.
///     - Nested `NavigationView`, which can cause navigation problems.
///     - Missing abstraction via protocols.
///   - Code Quality Issues:
///     - Use of magic numbers for padding, spacing, and frame dimensions.
///     - Hardcoded strings, reducing maintainability and localization support.
///   - Security Issues:
///     - Hardcoded secrets (e.g., API keys) present within the view.
///   - UI Issues:
///     - Lack of accessibility modifiers for interactive elements.
/// 
/// - Purpose:
///   - Serves as an educational example for identifying and remedying common issues in SwiftUI app architecture and development.
///   - Intended to be reviewed, refactored, and improved by following best practices for maintainability, security, and accessibility.
struct ArchitectureIssuesView: View {
    @State private var isLoading = false
    @State private var userName = ""
    @State private var userEmail = ""
    @State private var selectedTab = 0
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isEditing = false
    @State private var searchText = ""
    @State private var sortOrder = SortOrder.ascending
    @State private var filterType = FilterType.all
    
    // Architecture Issue: Missing dependency injection
    @StateObject private var userManager = UserManager()
    
    enum SortOrder {
        case ascending, descending
    }
    
    enum FilterType {
        case all, active, inactive
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Architecture Issue: Nested NavigationView
                NavigationView {
                    Text("Nested Navigation")
                }
                
                // Code Quality Issue: Magic numbers
                VStack(spacing: 16) {
                    Text("User Profile")
                        .font(.title)
                        .padding(20)
                    
                    TextField("Name", text: $userName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(16)
                    
                    TextField("Email", text: $userEmail)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(16)
                }
                .frame(width: 300, height: 200)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                
                // Code Quality Issue: Hardcoded strings
                Text("This is a very long hardcoded string that should be moved to a localization file " +
                     "for better internationalization support and maintainability.")
                    .padding()
                    .multilineTextAlignment(.center)
                
                // Security Issue: Hardcoded secret
                // swiftlint:disable:next redundant_discardable_let
                let _ = "sk-1234567890abcdef"
                
                // UI Issue: Missing accessibility
                Button {
                    showAlert = true
                    alertMessage = "Button tapped!"
                } label: {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                }
                .padding()
                
            }
            .navigationTitle("Architecture Issues")
            .alert("Alert", isPresented: $showAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
        }
    }
}

#Preview {
    ArchitectureIssuesView()
} 
