import SwiftUI

/// `NetworkingIssuesView` is a SwiftUI view that demonstrates various common networking and security issues.
/// 
/// ## Features
/// - Presents buttons to load data over the network in ways that highlight anti-patterns and mistakes.
/// - Displays the loaded data or any errors that occur.
/// - Shows a progress indicator while data is loading.
///
/// ## Demonstrated Issues
/// - **Hardcoded Secrets:** Contains hardcoded API keys, database passwords, and JWT tokens directly in source code,
///   which is a significant security risk.
/// - **Unsafe URL Construction:** Constructs URLs using string interpolation with user data and secrets, 
///   which can result in vulnerabilities and leaks.
/// - **Synchronous Networking on Main Thread:** Uses synchronous network requests (`Data(contentsOf:)`) in the UI,
///   which blocks the main thread and can freeze the UI.
/// - **Missing Error Handling:** Executes a network request without proper error checks, silently ignoring failures.
///
/// ## Usage
/// Use this view for educational or demonstration purposes only. Do not use as a pattern for production code.
///
/// - Warning: The patterns used here are intentionally insecure or incorrect for illustrative purposes.
///
struct NetworkingIssuesView: View {
    @State private var data: String = ""
    @State private var isLoading = false
    
    var body: some View {
        VStack {
            Text("Networking Issues Demo")
                .font(.title)
                .padding()
            
            // Security Issue: Hardcoded API key
            let apiKey = "sk-proj-1234567890abcdefghijklmnopqrstuvwxyz"
            
            // Security Issue: Unsafe URL construction
            let userId = "user123"
            let unsafeURL = URL(string: "https://api.example.com/users/\(userId)/data?key=\(apiKey)")!
            
            // Networking Issue: Synchronous networking
            Button("Load Data (Synchronous)") {
                do {
                    let url = URL(string: "https://jsonplaceholder.typicode.com/posts/1")!
                    let data = try Data(contentsOf: url)
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let title = json["title"] as? String {
                        self.data = title
                    }
                } catch {
                    self.data = "Error: \(error.localizedDescription)"
                }
            }
            .padding()
            .background(Color.red)
            .foregroundColor(.white)
            .cornerRadius(8)
            
            // Networking Issue: Missing error handling
            Button("Load Data (No Error Handling)") {
                isLoading = true
                let url = URL(string: "https://jsonplaceholder.typicode.com/posts/1")!
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    Task { @MainActor in
                        isLoading = false
                        if let data = data,
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let title = json["title"] as? String {
                            self.data = title
                        }
                    }
                }.resume()
            }
            .padding()
            .background(Color.orange)
            .foregroundColor(.white)
            .cornerRadius(8)
            
            if isLoading {
                ProgressView("Loading...")
                    .padding()
            }
            
            if !data.isEmpty {
                Text("Loaded Data:")
                    .font(.headline)
                    .padding(.top)
                
                Text(data)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            
            // Security Issue: More hardcoded secrets
            let databasePassword = "super_secret_password_123"
            let jwtToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
                "eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ." +
                "SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    NetworkingIssuesView()
} 
