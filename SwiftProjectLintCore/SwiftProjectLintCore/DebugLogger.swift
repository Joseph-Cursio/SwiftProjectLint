import Foundation

#if DEBUG
/// Shared debug logger for SwiftProjectLint - only compiled in DEBUG builds
public struct DebugLogger {
    public static let isEnabled = true
    
    /// Returns the path to the debug directory, creating it if necessary
    public static func debugDirectory() -> String {
        let projectRootPath = FileManager.default.currentDirectoryPath
        let debugDirectory = projectRootPath + "/debug_output"
        
        // Ensure debug directory exists
        do {
            try FileManager.default.createDirectory(atPath: debugDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("DEBUG: Failed to create debug directory: \(error)")
        }
        
        return debugDirectory
    }
    
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
    public static func logVisitor(_ visitor: VisitorType, _ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard isEnabled else { return }
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        print("DEBUG [\(fileName):\(line)] \(visitor.rawValue).\(function): \(message)")
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

// MARK: - VisitorType Enum

public enum VisitorType: String {
    case performance = "PerformanceVisitor"
    case viewRelationship = "ViewRelationshipVisitor"
    case ui = "UIVisitor"
    case stateVariable = "StateVariableVisitor"
    case memoryManagement = "MemoryManagementVisitor"
    case architecture = "ArchitectureVisitor"
    case codeQuality = "CodeQualityVisitor"
    case security = "SecurityVisitor"
    case accessibility = "AccessibilityVisitor"
    case networking = "NetworkingVisitor"
    case forEachSelfID = "ForEachSelfIDVisitor"
    case swiftUIManagement = "SwiftUIManagementVisitor"
    // Add any others as needed
} 