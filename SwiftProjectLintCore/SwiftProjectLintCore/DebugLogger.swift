import Foundation

#if DEBUG
/// Shared debug logger for SwiftProjectLint - only compiled in DEBUG builds
public struct DebugLogger {
    public static let isEnabled = true
    
    /// Log a debug message with file, function, and line information
    public static func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard isEnabled else { return }
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        print("DEBUG [\(fileName):\(line)] \(function): \(message)")
    }
    
    /// Log AST structure for debugging
    public static func logAST(_ ast: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard isEnabled else { return }
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        print("DEBUG [\(fileName):\(line)] \(function): AST Structure:")
        print(ast)
    }
    
    /// Log visitor-specific information
    public static func logVisitor(_ visitorName: String, _ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard isEnabled else { return }
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        print("DEBUG [\(fileName):\(line)] \(visitorName).\(function): \(message)")
    }
    
    /// Log issue detection
    public static func logIssue(_ issue: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard isEnabled else { return }
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        print("DEBUG [\(fileName):\(line)] \(function): ISSUE DETECTED: \(issue)")
    }
    
    /// Log syntax node traversal
    public static func logNode(_ nodeType: String, _ details: String = "", file: String = #file, function: String = #function, line: Int = #line) {
        guard isEnabled else { return }
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let detailsText = details.isEmpty ? "" : " - \(details)"
        print("DEBUG [\(fileName):\(line)] \(function): Visiting \(nodeType)\(detailsText)")
    }
}
#else
/// Empty debug logger for release builds
public struct DebugLogger {
    public static let isEnabled = false
    
    public static func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {}
    public static func logAST(_ ast: String, file: String = #file, function: String = #function, line: Int = #line) {}
    public static func logVisitor(_ visitorName: String, _ message: String, file: String = #file, function: String = #function, line: Int = #line) {}
    public static func logIssue(_ issue: String, file: String = #file, function: String = #function, line: Int = #line) {}
    public static func logNode(_ nodeType: String, _ details: String = "", file: String = #file, function: String = #function, line: Int = #line) {}
}
#endif 