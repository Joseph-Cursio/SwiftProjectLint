import Foundation
import SwiftUI

// MARK: - Models

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
struct StateVariable {
    let name: String
    let type: String
    let filePath: String
    let lineNumber: Int
    let viewName: String
    let propertyWrapper: String // @State, @StateObject, etc.
}

/// Represents a lint issue detected during static analysis of the project.
///
/// `LintIssue` describes a specific problem, warning, or suggestion found in the codebase. It includes the severity of the issue,
/// a descriptive message, and one or more locations where the issue occurs, as well as an optional suggestion for remediation.
///
/// - Parameters:
///   - severity: The severity of the issue (e.g., `.error`, `.warning`, `.info`). See `IssueSeverity`.
///   - message: A human-readable description of the detected issue.
///   - locations: One or more locations (file path and line number) where the issue was detected.
///   - suggestion: An optional fix or recommendation to resolve the issue, or `nil` if no suggestion is provided.
///   - ruleName: The identifier of the rule that generated this issue.
///
/// - Note: This struct supports multiple locations for a single issue. For backward compatibility, single-location
///         initializers and computed properties are provided.
///
/// - SeeAlso: `IssueSeverity`
public struct LintIssue: Identifiable {
    public let id: UUID = UUID()
    public let severity: IssueSeverity
    public let message: String
    /// The locations (file path and line number pairs) where the issue occurs.
    /// This supports issues that span multiple files or lines.
    public let locations: [(filePath: String, lineNumber: Int)]
    public let suggestion: String?
    public let ruleName: RuleIdentifier
    
    /// Returns the file path of the first location, or an empty string if no locations exist.
    public var filePath: String {
        return locations.first?.filePath ?? ""
    }
    
    /// Returns the line number of the first location, or 0 if no locations exist.
    public var lineNumber: Int {
        return locations.first?.lineNumber ?? 0
    }
    
    /// Initializes a lint issue with multiple locations.
    ///
    /// - Parameters:
    ///   - severity: The severity of the issue.
    ///   - message: The message describing the issue.
    ///   - locations: An array of file path and line number tuples where the issue occurs.
    ///   - suggestion: An optional suggestion for fixing the issue.
    ///   - ruleName: The identifier of the rule that generated this issue.
    public init(severity: IssueSeverity, message: String, locations: [(filePath: String, lineNumber: Int)], suggestion: String?, ruleName: RuleIdentifier) {
        self.severity = severity
        self.message = message
        self.locations = locations
        self.suggestion = suggestion
        self.ruleName = ruleName
    }
    
    /// Initializes a lint issue with a single location.
    /// For backward compatibility, this initializer populates the `locations` array with one element.
    ///
    /// - Parameters:
    ///   - severity: The severity of the issue.
    ///   - message: The message describing the issue.
    ///   - filePath: The file path where the issue occurs.
    ///   - lineNumber: The line number where the issue occurs.
    ///   - suggestion: An optional suggestion for fixing the issue.
    ///   - ruleName: The identifier of the rule that generated this issue.
    public init(severity: IssueSeverity, message: String, filePath: String, lineNumber: Int, suggestion: String?, ruleName: RuleIdentifier) {
        self.severity = severity
        self.message = message
        self.locations = [(filePath, lineNumber)]
        self.suggestion = suggestion
        self.ruleName = ruleName
    }
}

/// Represents the severity level of a lint issue detected by the linter.
///
/// Use `error` for serious problems that may cause project malfunction, `warning` for potential problems or code style issues,
/// and `info` for suggestions or informational notes that do not require immediate attention.
///
/// - Cases:
///   - error: Indicates a critical issue that should be fixed to ensure correct project behavior.
///   - warning: Indicates a potential issue or code style concern that may not break the project but is recommended to address.
///   - info: Provides informational messages or suggestions for improving code quality or consistency.
///
/// - SeeAlso: `LintIssue`
public enum IssueSeverity: String, Codable {
    case error
    case warning
    case info
}

/// Represents the hierarchical relationship and structure of a SwiftUI view within a project.
///
/// `ViewHierarchy` contains information about a specific view, including its name, its parent view (if any),
/// its direct child views, and a list of state variables declared within that view. This structure is useful for
/// analyzing and visualizing the component relationships in SwiftUI projects, as well as for detecting patterns and potential
/// issues related to state management and view composition.
///
/// - Parameters:
///   - viewName: The name of the SwiftUI view (typically the struct name).
///   - parentView: The name of the parent view, if one exists; otherwise `nil`.
///   - childViews: An array of names of direct child views included in this view's body.
///   - stateVariables: A list of `StateVariable` instances declared within this view.
///
/// - SeeAlso: `StateVariable`
struct ViewHierarchy {
    let viewName: String
    let parentView: String?
    let childViews: [String]
    let stateVariables: [StateVariable]
}

// MARK: - Project Linter

/// A class responsible for linting SwiftUI projects by analyzing project files, extracting state variables, 
/// building view hierarchies, and detecting various lint issues and patterns across the codebase.
/// 
/// The `ProjectLinter` traverses Swift source files, identifies property wrappers (such as `@State`, 
/// `@StateObject`), builds a map of state usage, and performs analysis to detect cross-file issues 
/// like duplicate state variables and cross-file patterns that might require refactoring or improvements.
/// 
/// - Important: Uses basic file and string matching operations. For comprehensive static analysis, 
/// integrating with a Swift parser is recommended.
/// 
/// - Note: The linter currently performs basic view hierarchy extraction and relies on simple regex 
/// patterns for detecting state variables. Extend methods to increase accuracy and coverage.
/// 
/// ## Usage Example
/// ```swift
/// let linter = ProjectLinter()
/// let issues = linter.analyzeProject(at: "/path/to/project")
/// for issue in issues {
///     print(issue.message)
/// }
/// ```
public class ProjectLinter {
    private var projectFiles: [String] = []
    private var stateVariables: [StateVariable] = []
    private var viewHierarchies: [ViewHierarchy] = []
    private var detector: SwiftSyntaxPatternDetector?
    
    /// Analyzes a SwiftUI project at the specified file system path, performing static analysis to detect state variable usage,
    /// build view hierarchies, and report lint issues and code patterns across all Swift source files in the project.
    ///
    /// - Parameters:
    ///   - path: The root directory path of the SwiftUI project to analyze.
    ///   - categories: Optional array of pattern categories to analyze. If nil, analyzes all categories.
    ///   - patternNames: Optional array of specific pattern names to analyze. If provided, overrides categories.
    /// - Returns: An array of `LintIssue` objects describing all detected issues, warnings, or suggestions throughout the project.
    @MainActor public func analyzeProject(at path: String, categories: [PatternCategory]? = nil, patternNames: [String]? = nil) -> [LintIssue] {
        print("DEBUG: analyzeProject called with path: '\(path)'")
        print("DEBUG: categories: \(categories?.map { String(describing: $0) } ?? ["all"])")
        print("DEBUG: patternNames: \(patternNames ?? [])")
        
        var issues: [LintIssue] = []
        projectFiles = findSwiftFiles(in: path)
        
        print("DEBUG: Found \(projectFiles.count) project files for analysis")
        
        for filePath in projectFiles {
            let fileIssues = analyzeSwiftFile(at: filePath, categories: categories, patternNames: patternNames)
            issues.append(contentsOf: fileIssues)
        }
        
        buildViewHierarchy()
        let crossFileIssues = detectCrossFileIssues(categories: categories)
        issues.append(contentsOf: crossFileIssues)
        
        // Run cross-file pattern detection using SwiftSyntax, respecting enabled patterns or categories
        let swiftSyntaxDetector = detector ?? SwiftSyntaxPatternDetector()
        let crossFilePatternIssues: [LintIssue]
        if let patternNames = patternNames {
            crossFilePatternIssues = swiftSyntaxDetector.detectCrossFilePatterns(projectFiles: projectFiles, patternNames: patternNames)
        } else {
            crossFilePatternIssues = swiftSyntaxDetector.detectCrossFilePatterns(projectFiles: projectFiles, categories: categories)
        }
        issues.append(contentsOf: crossFilePatternIssues)
        
        print("DEBUG: analyzeProject returning \(issues.count) total issues")
        return issues
    }
    
    /// Recursively locates all Swift source files (`.swift` files) within a specified directory path.
    ///
    /// This method uses the file system to traverse the directory at the given path and any of its subdirectories,
    /// collecting the full file paths of all files with a `.swift` extension. The resulting array of file paths
    /// can be used for further analysis or processing.
    ///
    /// - Parameter path: The root directory path to begin searching for Swift files.
    /// - Returns: An array of full file system paths (as `String`) for each `.swift` file found in the directory
    ///            and all of its subdirectories. If the directory cannot be enumerated, the returned array will be empty.
    ///
    /// - Note: Hidden files and directories are included in the search. The search is case-sensitive and will only
    ///         locate files ending in `.swift`.
    internal func findSwiftFiles(in path: String) -> [String] {
        print("DEBUG: findSwiftFiles called with path: '\(path)'")
        
        let fileManager = FileManager.default
        var swiftFiles: [String] = []
        
        // Check if path exists
        let pathExists = fileManager.fileExists(atPath: path)
        print("DEBUG: Path exists check: \(pathExists)")
        guard pathExists else {
            print("DEBUG: Path does not exist: '\(path)'")
            return swiftFiles
        }
        
        // Check if path is a directory
        var isDirectory: ObjCBool = false
        let isDirCheck = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
        print("DEBUG: Is directory check: \(isDirCheck), isDirectory: \(isDirectory.boolValue)")
        guard isDirCheck, isDirectory.boolValue else {
            print("DEBUG: Path is not a directory: '\(path)'")
            return swiftFiles
        }
        
        // Try to list contents directly first
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: path)
            print("DEBUG: Directory contents (first 10): \(contents.prefix(10))")
        } catch {
            print("DEBUG: Error listing directory contents: \(error)")
        }
        
        print("DEBUG: Creating enumerator...")
        guard let enumerator = fileManager.enumerator(atPath: path) else {
            print("DEBUG: Could not create enumerator for path: '\(path)'")
            return swiftFiles
        }
        print("DEBUG: Enumerator created successfully")
        
        var fileCount = 0
        var allFiles: [String] = []
        while let filePath = enumerator.nextObject() as? String {
            fileCount += 1
            allFiles.append(filePath)
            if filePath.hasSuffix(".swift") {
                let fullPath = (path as NSString).appendingPathComponent(filePath)
                swiftFiles.append(fullPath)
                print("DEBUG: Found Swift file: '\(fullPath)'")
            }
        }
        print("DEBUG: Enumerated \(fileCount) total files")
        print("DEBUG: All files found: \(allFiles.prefix(20))")
        
        print("DEBUG: findSwiftFiles returning \(swiftFiles.count) Swift files")
        return swiftFiles
    }
    
    /// Analyzes a single Swift source file for SwiftUI state variable usage and potential code issues.
    ///
    /// This method performs the following steps:
    /// 1. Reads the contents of the specified Swift file at the given path.
    /// 2. Iterates through each line of the file, attempting to extract property declarations that use
    ///    SwiftUI state-related property wrappers such as `@State`, `@StateObject`, `@ObservedObject`, or `@EnvironmentObject`.
    ///    Any detected state variable is appended to the internal `stateVariables` collection.
    /// 3. Performs additional pattern-based lint analysis using the `SwiftSyntaxPatternDetector`, appending any issues detected.
    /// 4. Returns an array of `LintIssue` objects representing all issues found within the file.
    ///
    /// - Parameters:
    ///   - path: The full filesystem path to the Swift source file to be analyzed.
    ///   - categories: Optional array of pattern categories to analyze. If nil, analyzes all categories.
    ///   - patternNames: Optional array of specific pattern names to analyze. If provided, overrides categories.
    /// - Returns: An array of `LintIssue` objects describing all code issues, warnings, or suggestions detected
    ///            within the file.
    ///
    /// - Note: This method uses basic regular expressions and line-based parsing, so it may not recognize all valid Swift syntax
    ///         or handle edge cases (such as multiline property declarations or complex type signatures).
    ///         For comprehensive and robust analysis, integration with a Swift syntax parser is recommended.
    private func analyzeSwiftFile(at path: String, categories: [PatternCategory]? = nil, patternNames: [String]? = nil) -> [LintIssue] {
        var issues: [LintIssue] = []
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return issues
        }
        
        // jdc: this is evidently the regex pattern version 
        let lines = content.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if let stateVar = extractStateVariable(from: trimmedLine, filePath: path, lineNumber: index + 1) {
                stateVariables.append(stateVar)
            }
        }
        
        // Use SwiftSyntaxPatternDetector for comprehensive analysis, respecting enabled patterns or categories
        let swiftSyntaxDetector = detector ?? SwiftSyntaxPatternDetector()
        if let patternNames = patternNames {
            issues.append(contentsOf: swiftSyntaxDetector.detectPatterns(in: content, filePath: path, patternNames: patternNames))
        } else {
            issues.append(contentsOf: swiftSyntaxDetector.detectPatterns(in: content, filePath: path, categories: categories))
        }
        return issues
    }
    
    /// Attempts to extract a `StateVariable` instance from a line of Swift code, if the line declares a property using a recognized SwiftUI property wrapper.
    ///
    /// This method scans the given line of source code for declarations of properties using the `@State`, `@StateObject`, `@ObservedObject`, or `@EnvironmentObject` property wrappers. If a matching declaration is found, it parses out the variable's name and type and constructs a corresponding `StateVariable` model, capturing the context of the declaration (file path, line number, view name, and property wrapper).
    ///
    /// - Parameters:
    ///   - line: The line of Swift code to analyze (typically a single trimmed line representing a property declaration).
    ///   - filePath: The full path of the source file containing the line.
    ///   - lineNumber: The 1-based line number of the line within the file.
    /// - Returns: A `StateVariable` if a property with a recognized property wrapper is found in the line; otherwise, `nil`.
    ///
    /// - Note: Extraction is based on simple regular expressions and may not capture all edge cases or complex property declarations. For more robust analysis, a Swift syntax parser is recommended.
    private func extractStateVariable(from line: String, filePath: String, lineNumber: Int) -> StateVariable? {
        // Basic regex patterns for state variables
        let statePatterns = [
            "@State\\s+var\\s+(\\w+)\\s*:\\s*(\\w+)",
            "@StateObject\\s+var\\s+(\\w+)\\s*:\\s*(\\w+)",
            "@ObservedObject\\s+var\\s+(\\w+)\\s*:\\s*(\\w+)",
            "@EnvironmentObject\\s+var\\s+(\\w+)\\s*:\\s*(\\w+)"
        ]
        
        for pattern in statePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) {
                
                let nameRange = match.range(at: 1)
                let typeRange = match.range(at: 2)
                
                if let name = extractString(from: line, range: nameRange),
                   let type = extractString(from: line, range: typeRange) {
                    
                    let propertyWrapper = extractPropertyWrapper(from: line)
                    let viewName = extractViewName(from: filePath) // Simplified
                    
                    return StateVariable(
                        name: name,
                        type: type,
                        filePath: filePath,
                        lineNumber: lineNumber,
                        viewName: viewName,
                        propertyWrapper: propertyWrapper
                    )
                }
            }
        }
        
        return nil
    }
    
    /// Extracts a substring from the given line of text using the provided `NSRange`.
    ///
    /// This method returns the substring of `line` that corresponds to the specified `range`.
    /// If the range is not valid (i.e., `NSNotFound`), the method returns `nil`.
    ///
    /// - Parameters:
    ///   - line: The string from which to extract a substring.
    ///   - range: The `NSRange` specifying the start location and length of the substring to extract.
    /// - Returns: The substring corresponding to the `range` within `line`, or `nil` if the range is invalid.
    ///
    /// - Note: This method assumes that the range is valid within the bounds of `line`.
    ///         If the range exceeds the length of the string or is not found, `nil` is returned.
    private func extractString(from line: String, range: NSRange) -> String? {
        guard range.location != NSNotFound else { return nil }
        let startIndex = line.index(line.startIndex, offsetBy: range.location)
        let endIndex = line.index(startIndex, offsetBy: range.length)
        return String(line[startIndex..<endIndex])
    }
    
    /// Extracts the property wrapper annotation (such as `@State`, `@StateObject`, `@ObservedObject`, or `@EnvironmentObject`)
    /// from a line of Swift code.
    ///
    /// This method scans the provided line of text for known SwiftUI state property wrappers and returns the first one found.
    /// If none of the recognized property wrappers are present, it returns `"Unknown"`.
    ///
    /// - Parameter line: A single line of Swift source code, typically representing a property declaration.
    /// - Returns: A string representing the property wrapper used in the line (e.g., `"@State"`), or `"Unknown"`
    ///            if no recognized wrapper is present.
    private func extractPropertyWrapper(from line: String) -> String {
        if line.contains("@State") { return "@State" }
        if line.contains("@StateObject") { return "@StateObject" }
        if line.contains("@ObservedObject") { return "@ObservedObject" }
        if line.contains("@EnvironmentObject") { return "@EnvironmentObject" }
        return "Unknown"
    }
    
    /// Extracts the name of a SwiftUI view from a given file path.
    ///
    /// This method assumes that the file name (excluding the `.swift` extension) corresponds to the
    /// name of the SwiftUI view defined in that file. For example, given a file path like 
    /// `/Users/example/Project/MyCustomView.swift`, this method will return `"MyCustomView"`.
    ///
    /// - Parameter filePath: The full file system path of the Swift source file.
    /// - Returns: The inferred view name, derived from the file name with the `.swift` extension removed.
    ///
    /// - Note: This approach relies on the convention that each SwiftUI view is declared in a file
    ///         named after the view's struct. If a file contains multiple views or does not follow this
    ///         naming convention, the returned name may not accurately reflect the view's actual type name.
    private func extractViewName(from filePath: String) -> String {
        let fileName = (filePath as NSString).lastPathComponent
        return fileName.replacingOccurrences(of: ".swift", with: "")
    }
    
    /// Constructs the view hierarchy for all SwiftUI views detected in the project.
    ///
    /// This method analyzes the collected `stateVariables` to group state properties by their corresponding views.
    /// For each unique view (identified by its name), it creates a `ViewHierarchy` instance that includes the view's name,
    /// its declared state variables, and placeholder values for `parentView` and `childViews` (which are not currently analyzed
    /// in detail). The resulting hierarchies are stored in the `viewHierarchies` array for later cross-file analysis and
    /// reporting.
    ///
    /// - Note: The current implementation only establishes a flat hierarchy based on state variable grouping and does not
    ///         determine actual parent-child relationships between views. Future enhancements may analyze the contents of
    ///         view bodies to detect nested view compositions and improve hierarchy accuracy.
    ///
    /// - SeeAlso: `ViewHierarchy`, `stateVariables`
    private func buildViewHierarchy() {
        // This would analyze view relationships
        // For now, we'll create a simple structure
        let viewNames = Set(stateVariables.map { $0.viewName })
        
        for viewName in viewNames {
            let viewStateVars = stateVariables.filter { $0.viewName == viewName }
            let hierarchy = ViewHierarchy(
                viewName: viewName,
                parentView: nil, // Would be determined by analysis
                childViews: [], // Would be determined by analysis
                stateVariables: viewStateVars
            )
            viewHierarchies.append(hierarchy)
        }
    }
    
    /// Detects lint issues that span multiple Swift files, specifically targeting state variable declarations
    /// that appear with the same name across different views (potentially causing source-of-truth or state propagation problems).
    ///
    /// - Parameters:
    ///   - categories: Optional array of pattern categories to analyze. If nil, analyzes all categories.
    /// - Returns: An array of `LintIssue`
    @MainActor private func detectCrossFileIssues(categories: [PatternCategory]? = nil) -> [LintIssue] {
        var issues: [LintIssue] = []
        // Note: State management cross-file issues are now handled by SwiftSyntax cross-file visitors
        // This method is kept for potential future cross-file analysis that doesn't fit the SwiftSyntax pattern model
        return issues
    }
    
    public init() {}
    
    /// Sets the SwiftSyntax pattern detector to use for analysis.
    /// This allows the ProjectLinter to use a configured detector with registered patterns.
    ///
    /// - Parameter detector: The configured SwiftSyntaxPatternDetector to use.
    public func setDetector(_ detector: SwiftSyntaxPatternDetector) {
        self.detector = detector
    }
}
