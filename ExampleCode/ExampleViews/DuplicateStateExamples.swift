import SwiftUI

// Example of duplicate state variables in parent and child views
// This demonstrates a code smell that SwiftProjectLint should detect

struct ParentView: View {
    @State private var isLoading: Bool = false
    @State private var userName: String = ""
    @State private var showAlert: Bool = false
    
    var body: some View {
        VStack {
            Text("Parent View")
            
            if isLoading {
                ProgressView("Loading...")
            }
            
            TextField("Enter username", text: $userName)
            
            Button("Show Child") {
                showAlert = true
            }
            
            ChildView()
        }
        .alert("Alert", isPresented: $showAlert) {
            Button("OK") { }
        }
    }
}

struct ChildView: View {
    // Duplicate state variables - this is problematic!
    @State private var isLoading: Bool = false
    @State private var userName: String = ""
    @State private var showAlert: Bool = false
    
    var body: some View {
        VStack {
            Text("Child View")
            
            if isLoading {
                ProgressView("Child Loading...")
            }
            
            TextField("Child username", text: $userName)
            
            Button("Child Alert") {
                showAlert = true
            }
            
            Button("Toggle Loading") {
                isLoading.toggle()
            }
        }
        .alert("Child Alert", isPresented: $showAlert) {
            Button("OK") { }
        }
        .padding()
        .border(Color.blue)
    }
}

// Another example with nested child views
struct GrandparentView: View {
    @State private var counter: Int = 0
    @State private var message: String = "Hello"
    
    var body: some View {
        VStack {
            Text("Grandparent: \(counter)")
            Text(message)
            
            ParentWithDuplicateState()
        }
    }
}

struct ParentWithDuplicateState: View {
    @State private var counter: Int = 0  // Duplicate from grandparent
    @State private var isVisible: Bool = true
    
    var body: some View {
        VStack {
            if isVisible {
                Text("Parent: \(counter)")
                
                ChildWithDuplicateState()
            }
        }
    }
}

struct ChildWithDuplicateState: View {
    @State private var counter: Int = 0     // Duplicate from parent and grandparent
    @State private var isVisible: Bool = true  // Duplicate from parent
    @State private var data: [String] = []
    
    var body: some View {
        VStack {
            if isVisible {
                Text("Child: \(counter)")
                
                ForEach(data, id: \.self) { item in
                    Text(item)
                }
                
                DeepChildView()
            }
        }
    }
}

struct DeepChildView: View {
    @State private var counter: Int = 0     // Yet another duplicate
    @State private var data: [String] = []  // Duplicate from parent
    @State private var isActive: Bool = false
    
    var body: some View {
        HStack {
            Text("Deep Child: \(counter)")
            
            if isActive {
                Text("Active")
            }
        }
    }
}

// Example with different types but same variable names
struct TypeDuplicateParent: View {
    @State private var value: Int = 0
    @State private var items: [String] = []
    
    var body: some View {
        VStack {
            Text("Value: \(value)")
            TypeDuplicateChild()
        }
    }
}

struct TypeDuplicateChild: View {
    @State private var value: Double = 0.0  // Same name, different type
    @State private var items: [Int] = []    // Same name, different type
    
    var body: some View {
        VStack {
            Text("Value: \(value)")
            Text("Items count: \(items.count)")
        }
    }
}
