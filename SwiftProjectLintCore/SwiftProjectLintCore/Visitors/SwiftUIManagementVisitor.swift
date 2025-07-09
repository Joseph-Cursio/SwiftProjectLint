import Foundation
import SwiftParser
import SwiftSyntax

// MARK: - SwiftUI Management Visitor

/// A SwiftSyntax visitor that detects state management patterns and anti-patterns in SwiftUI code.
///
/// `SwiftUIManagementVisitor` analyzes SwiftUI property wrappers and state variable declarations
/// to identify issues such as duplicate state variables, missing @StateObject usage, uninitialized
/// state, and inefficient state sharing patterns.
///
/// ### Detected Patterns:
/// - Duplicate state variables across related views
/// - Missing @StateObject usage for ObservableObjects
/// - Uninitialized state variables
/// - Unused state variables
/// - Inefficient state sharing patterns
///
/// ### Usage:
/// ```swift
/// let visitor = SwiftUIManagementVisitor()
/// visitor.walk(sourceFile)
/// let issues = visitor.detectedIssues
/// ```
class SwiftUIManagementVisitor: BasePatternVisitor {
    
    // MARK: - Configuration
    
    struct Configuration {
        let enableCrossFileAnalysis: Bool
        let maxStateVariables: Int
        let checkForDuplicates: Bool
        let checkForUnused: Bool
        
        static let `default` = Configuration(
            enableCrossFileAnalysis: true,
            maxStateVariables: 5,
            checkForDuplicates: true,
            checkForUnused: true
        )
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    internal var stateVariables: [StateVariableInfo] = []
    private var currentViewName: String = ""
    private var currentFilePath: String = ""
    private var viewDeclarations: [ViewDeclaration] = []
    
    // MARK: - Initialization
    
    required init(patternCategory: PatternCategory) {
        self.config = .default
        super.init(viewMode: .sourceAccurate)
    }
    
    required init(viewMode: SyntaxTreeViewMode) {
        self.config = .default
        super.init(viewMode: viewMode)
    }
    
    // MARK: - Syntax Visitor Methods
    
    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        // Extract file path from the node if possible
        // For now, we'll need to set this externally
        return .visitChildren
    }
    
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        DebugLogger.logVisitor(.swiftUIManagement, "Visiting struct: \(node.name.text)")
        // Check if this is a SwiftUI view
        if isSwiftUIView(node) {
            let viewName = node.name.text
            currentViewName = viewName
            
            // Analyze the view structure
            analyzeViewStructure(node)
        }
        
        return .visitChildren
    }
    
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Analyze variable declarations for state management patterns
        analyzeVariableDeclaration(node)
        return .visitChildren
    }
    
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check for unused state variables in functions
        if config.checkForUnused {
            analyzeFunctionForUnusedState(node)
        }
        return .visitChildren
    }
    
    // MARK: - Analysis Methods
    
    private func analyzeViewStructure(_ node: StructDeclSyntax) {
        let stateCount = countStateVariables(in: node)
        
        // Check for fat view pattern
        if stateCount > config.maxStateVariables {
            // Try to use pattern template first, fallback to hardcoded message
            if currentPattern != nil {
                addIssueWithTemplate(
                    filePath: currentFilePath,
                    lineNumber: getLineNumber(for: node),
                    variables: [
                        "viewName": currentViewName,
                        "stateCount": String(stateCount)
                    ]
                )
            } else {
                addIssue(
                    severity: .warning,
                    message: "View '\(currentViewName)' has \(stateCount) state variables, consider MVVM pattern",
                    filePath: currentFilePath,
                    lineNumber: getLineNumber(for: node),
                    suggestion: "Extract business logic into an ObservableObject ViewModel",
                    ruleName: nil
                )
            }
        }
        
        // Store view declaration for cross-file analysis
        let viewDeclaration = ViewDeclaration(
            name: currentViewName,
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: node),
            stateVariables: stateVariables.filter { $0.viewName == currentViewName }
        )
        viewDeclarations.append(viewDeclaration)
    }
    
    private func analyzeVariableDeclaration(_ node: VariableDeclSyntax) {
        for binding in node.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            
            let variableName = pattern.identifier.text
            let propertyWrapper = extractPropertyWrapper(from: node)
            let typeAnnotation = extractTypeAnnotation(from: binding)
            let hasInitialValue = binding.initializer != nil
            
            // Create state variable info
            let stateVar = StateVariableInfo(
                name: variableName,
                type: typeAnnotation,
                propertyWrapper: propertyWrapper,
                viewName: currentViewName,
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: node),
                hasInitialValue: hasInitialValue
            )
            
            stateVariables.append(stateVar)
            
            // Check for specific patterns
            checkForMissingStateObject(stateVar, node: node)
            checkForUninitializedState(stateVar, node: node)
            checkForUnusedState(stateVar, node: node)
        }
    }
    
    private func analyzeFunctionForUnusedState(_ node: FunctionDeclSyntax) {
        // This would analyze function bodies to check if state variables are used
        // Implementation would traverse the function body and check for variable usage
    }
    
    // MARK: - Pattern Detection Methods
    
    private func checkForMissingStateObject(_ stateVar: StateVariableInfo, node: VariableDeclSyntax) {
        guard stateVar.propertyWrapper == "@ObservedObject" else { return }
        
        // Check if this looks like it should be @StateObject
        let typeName = stateVar.type
        if typeName.hasSuffix("Manager") || 
           typeName.hasSuffix("Service") || 
           typeName.hasSuffix("Store") || 
           typeName.hasSuffix("ViewModel") {
            
            // Try to use pattern template first, fallback to hardcoded message
            if currentPattern != nil {
                addIssueWithTemplate(
                    filePath: stateVar.filePath,
                    lineNumber: stateVar.lineNumber,
                    variables: [
                        "variableName": stateVar.name
                    ]
                )
            } else {
                addIssue(
                    severity: .warning,
                    message: "Consider using @StateObject for '\(stateVar.name)' as it appears to be owned by this view",
                    filePath: stateVar.filePath,
                    lineNumber: stateVar.lineNumber,
                    suggestion: "Use @StateObject for ObservableObject properties that should be owned by this view"
                )
            }
        }
    }
    
    private func checkForUninitializedState(_ stateVar: StateVariableInfo, node: VariableDeclSyntax) {
        // Check if @State variable has an initial value
        if stateVar.propertyWrapper == "@State" {
            let hasInitialValue = node.bindings.contains { binding in
                binding.initializer != nil
            }
            
            if !hasInitialValue {
                // Try to use pattern template first, fallback to hardcoded message
                if currentPattern != nil {
                    addIssueWithTemplate(
                        filePath: stateVar.filePath,
                        lineNumber: stateVar.lineNumber,
                        variables: [
                            "variableName": stateVar.name
                        ]
                    )
                } else {
                    addIssue(
                        severity: .error,
                        message: "State variable '\(stateVar.name)' must have an initial value",
                        filePath: stateVar.filePath,
                        lineNumber: stateVar.lineNumber,
                        suggestion: "Provide an initial value for the state variable"
                    )
                }
            }
        }
    }
    
    private func checkForUnusedState(_ stateVar: StateVariableInfo, node: VariableDeclSyntax) {
        // This would require more sophisticated analysis to determine if a state variable is actually used
        // For now, we'll implement a basic check
        if stateVar.propertyWrapper == "@State" && stateVar.hasInitialValue {
            // Check if the variable is referenced in the view body
            // This is a simplified check - in practice, you'd need to analyze the entire view body
        }
    }
    
    // MARK: - Cross-File Analysis
    
    func performCrossFileAnalysis() {
        guard config.checkForDuplicates else { return }
        
        // Group state variables by name
        let groupedByName = Dictionary(grouping: stateVariables) { $0.name }
        
        for (variableName, variables) in groupedByName {
            if variables.count > 1 {
                // Check if these are in related views
                let relatedViews = findRelatedViews(for: variables)
                
                if !relatedViews.isEmpty {
                    addDuplicateStateIssue(
                        variableName: variableName,
                        variables: variables,
                        relatedViews: relatedViews
                    )
                }
            }
        }
    }
    
    func findRelatedViews(for variables: [StateVariableInfo]) -> [String] {
        // For single-file analysis, we'll consider all views as potentially related
        // since we don't have cross-file relationship information
        return Array(Set(variables.map { $0.viewName }))
    }
    
    private func addDuplicateStateIssue(
        variableName: String,
        variables: [StateVariableInfo],
        relatedViews: [String]
    ) {
        let viewNames = relatedViews.joined(separator: ", ")
        let firstVariable = variables.first!
        
        // Try to use pattern template first, fallback to hardcoded message
        if currentPattern != nil {
            addIssueWithTemplate(
                filePath: firstVariable.filePath,
                lineNumber: firstVariable.lineNumber,
                variables: [
                    "variableName": variableName,
                    "viewNames": viewNames
                ]
            )
        } else {
            addIssue(
                severity: .warning,
                message: "Duplicate state variable '\(variableName)' found in related views: \(viewNames)",
                filePath: firstVariable.filePath,
                lineNumber: firstVariable.lineNumber,
                suggestion: "Create a shared ObservableObject for '\(variableName)' and inject it via .environmentObject() at the root level."
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func isSwiftUIView(_ node: StructDeclSyntax) -> Bool {
        // Check if the struct conforms to View protocol
        for inheritance in node.inheritanceClause?.inheritedTypes ?? [] {
            if inheritance.type.as(IdentifierTypeSyntax.self)?.name.text == "View" {
                return true
            }
        }
        return false
    }
    
    private func extractPropertyWrapper(from node: VariableDeclSyntax) -> String {
        for attribute in node.attributes {
            if let attributeSyntax = attribute.as(AttributeSyntax.self),
               let attributeName = attributeSyntax.attributeName.as(IdentifierTypeSyntax.self) {
                return "@\(attributeName.name.text)"
            }
        }
        return ""
    }
    
    private func extractTypeAnnotation(from binding: PatternBindingSyntax) -> String {
        if let typeAnnotation = binding.typeAnnotation {
            return typeAnnotation.type.description.trimmingCharacters(in: .whitespaces)
        }
        return ""
    }
    
    private func countStateVariables(in node: StructDeclSyntax) -> Int {
        var count = 0
        for member in node.memberBlock.members {
            if let variableDecl = member.decl.as(VariableDeclSyntax.self) {
                let propertyWrapper = extractPropertyWrapper(from: variableDecl)
                if propertyWrapper.hasPrefix("@State") || propertyWrapper.hasPrefix("@StateObject") {
                    count += variableDecl.bindings.count
                }
            }
        }
        return count
    }
    
    // MARK: - Public Interface
    
    /// Sets the current file path for issue reporting.
    ///
    /// - Parameter filePath: The file path to set.
    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }
    
    /// Performs cross-file analysis after all files have been processed.
    func finalizeAnalysis() {
        performCrossFileAnalysis()
    }
    
    // MARK: - Helper Methods
    
    override func getLineNumber(for node: Syntax) -> Int {
        guard let converter = sourceLocationConverter else { return 1 }
        let position = node.positionAfterSkippingLeadingTrivia
        let location = converter.location(for: position)
        return location.line
    }
    
    func getLineNumber(for node: StructDeclSyntax) -> Int {
        guard let converter = sourceLocationConverter else { return 1 }
        let position = node.positionAfterSkippingLeadingTrivia
        let location = converter.location(for: position)
        return location.line
    }
    
    func getLineNumber(for node: VariableDeclSyntax) -> Int {
        guard let converter = sourceLocationConverter else { return 1 }
        let position = node.positionAfterSkippingLeadingTrivia
        let location = converter.location(for: position)
        return location.line
    }
}

// MARK: - Supporting Types

/// Information about a state variable detected during analysis.
struct StateVariableInfo {
    let name: String
    let type: String
    let propertyWrapper: String
    let viewName: String
    let filePath: String
    let lineNumber: Int
    let hasInitialValue: Bool
}

/// Information about a view declaration detected during analysis.
struct ViewDeclaration {
    let name: String
    let filePath: String
    let lineNumber: Int
    let stateVariables: [StateVariableInfo]
}

// MARK: - Cross-File SwiftUI Management Visitor

/// A cross-file version of SwiftUIManagementVisitor that can analyze patterns across multiple files.
class CrossFileSwiftUIManagementVisitor: SwiftUIManagementVisitor, CrossFilePatternVisitor {
    let fileCache: [String: SourceFileSyntax]
    private var parentChildRelationships: [String: Set<String>] = [:] // parent -> children (direct containment)
    private var navigationRelationships: [String: Set<String>] = [:] // parent -> children (navigation)
    private var modalRelationships: [String: Set<String>] = [:] // parent -> children (modal presentations)
    
    required init(fileCache: [String: SourceFileSyntax]) {
        self.fileCache = fileCache
        super.init(patternCategory: .stateManagement)
        print("DEBUG: CrossFileSwiftUIManagementVisitor initialized with \(fileCache.count) files")
    }
    
    required init(patternCategory: PatternCategory) {
        self.fileCache = [:]
        super.init(viewMode: .sourceAccurate)
    }
    
    required init(viewMode: SyntaxTreeViewMode) {
        self.fileCache = [:]
        super.init(viewMode: viewMode)
    }
    
    override func finalizeAnalysis() {
        // Build view relationships first
        buildViewRelationships()
        
        // Log all detected view relationships by type
        print("DEBUG: Parent-Child Relationships (Direct Containment):")
        for (parent, children) in parentChildRelationships {
            print("  \(parent) -> \(Array(children))")
        }
        print("DEBUG: Navigation Relationships:")
        for (parent, children) in navigationRelationships {
            print("  \(parent) -> \(Array(children))")
        }
        print("DEBUG: Modal Relationships:")
        for (parent, children) in modalRelationships {
            print("  \(parent) -> \(Array(children))")
        }
        // Log all detected state variables
        print("DEBUG: State Variables:")
        for variable in stateVariables {
            print("  [\(variable.viewName)] @State var \(variable.name): \(variable.type)")
        }
        // Perform enhanced cross-file analysis with access to all files
        performEnhancedCrossFileAnalysis()
    }
    
    private func buildViewRelationships() {
        // Analyze all files to build parent-child view relationships
        for (filePath, sourceFile) in fileCache {
            let sourceContents = sourceFile.description
            let sourceLocationConverter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
            
            // Extract view names from the file
            let viewNames = extractViewNames(from: sourceFile)
            
            for viewName in viewNames {
                let visitor = ViewRelationshipVisitor(
                    parentView: viewName,
                    filePath: filePath,
                    sourceContents: sourceContents,
                    sourceLocationConverter: sourceLocationConverter
                )
                visitor.walk(sourceFile)
                
                // Convert ViewRelationship to our internal format, categorized by type
                for relationship in visitor.relationships {
                    switch relationship.relationshipType {
                    case .directChild:
                        if parentChildRelationships[relationship.parentView] == nil {
                            parentChildRelationships[relationship.parentView] = []
                        }
                        parentChildRelationships[relationship.parentView]?.insert(relationship.childView)
                        
                    case .navigationDestination:
                        if navigationRelationships[relationship.parentView] == nil {
                            navigationRelationships[relationship.parentView] = []
                        }
                        navigationRelationships[relationship.parentView]?.insert(relationship.childView)
                        
                    case .sheet, .fullScreenCover, .popover, .alert:
                        if modalRelationships[relationship.parentView] == nil {
                            modalRelationships[relationship.parentView] = []
                        }
                        modalRelationships[relationship.parentView]?.insert(relationship.childView)
                        
                    case .tabView:
                        // TabView relationships are treated as navigation-like
                        if navigationRelationships[relationship.parentView] == nil {
                            navigationRelationships[relationship.parentView] = []
                        }
                        navigationRelationships[relationship.parentView]?.insert(relationship.childView)
                    }
                }
            }
        }
    }
    
    private func extractViewNames(from sourceFile: SourceFileSyntax) -> [String] {
        let visitor = ViewNameExtractorVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        return visitor.viewNames
    }
    
    private func performEnhancedCrossFileAnalysis() {
        // Always perform cross-file analysis for the enhanced visitor
        
        // Group state variables by name
        let groupedByName = Dictionary(grouping: stateVariables) { $0.name }
        
        for (variableName, variables) in groupedByName {
            if variables.count > 1 {
                // Check for different types of relationships separately
                
                // 1. Parent-child relationships (direct containment)
                let parentChildRelatedViews = findRelatedViews(for: variables)
                if !parentChildRelatedViews.isEmpty {
                    addDuplicateStateIssue(
                        variableName: variableName,
                        variables: variables,
                        relatedViews: parentChildRelatedViews,
                        relationshipType: "parent-child"
                    )
                }
                
                // 2. Navigation relationships
                let navigationRelatedViews = findNavigationRelatedViews(for: variables)
                if !navigationRelatedViews.isEmpty {
                    addDuplicateStateIssue(
                        variableName: variableName,
                        variables: variables,
                        relatedViews: navigationRelatedViews,
                        relationshipType: "navigation"
                    )
                }
                
                // 3. Modal relationships
                let modalRelatedViews = findModalRelatedViews(for: variables)
                if !modalRelatedViews.isEmpty {
                    addDuplicateStateIssue(
                        variableName: variableName,
                        variables: variables,
                        relatedViews: modalRelatedViews,
                        relationshipType: "modal"
                    )
                }
            }
        }
    }
    
    private func addDuplicateStateIssue(
        variableName: String,
        variables: [StateVariableInfo],
        relatedViews: [String],
        relationshipType: String
    ) {
        let viewNames = relatedViews.joined(separator: ", ")
        let firstVariable = variables.first!
        
        // Create relationship-specific messages
        let message: String
        let suggestion: String
        
        switch relationshipType {
        case "parent-child":
            message = "Duplicate state variable '\(variableName)' found in parent-child views: \(viewNames)"
            suggestion = "Create a shared ObservableObject for '\(variableName)' and pass it from parent to child using @ObservedObject."
        case "navigation":
            message = "Duplicate state variable '\(variableName)' found in navigation-related views: \(viewNames)"
            suggestion = "Create a shared ObservableObject for '\(variableName)' and inject it via .environmentObject() at the navigation root level."
        case "modal":
            message = "Duplicate state variable '\(variableName)' found in modal presentation views: \(viewNames)"
            suggestion = "Create a shared ObservableObject for '\(variableName)' and pass it to the modal view using @ObservedObject or @StateObject."
        default:
            message = "Duplicate state variable '\(variableName)' found in related views: \(viewNames)"
            suggestion = "Create a shared ObservableObject for '\(variableName)' and inject it via .environmentObject() at the root level."
        }
        
        // Try to use pattern template first, fallback to hardcoded message
        if currentPattern != nil {
            addIssueWithTemplate(
                filePath: firstVariable.filePath,
                lineNumber: firstVariable.lineNumber,
                variables: [
                    "variableName": variableName,
                    "viewNames": viewNames,
                    "relationshipType": relationshipType
                ]
            )
        } else {
            addIssue(
                severity: .warning,
                message: message,
                filePath: firstVariable.filePath,
                lineNumber: firstVariable.lineNumber,
                suggestion: suggestion
            )
        }
    }
    
    override func findRelatedViews(for variables: [StateVariableInfo]) -> [String] {
        let viewNames = Set(variables.map { $0.viewName })
        var relatedViews: Set<String> = []
        
        // Check for parent-child relationships (direct containment)
        for viewName in viewNames {
            // Check if this view has children that also have the same state variable
            if let children = parentChildRelationships[viewName] {
                for child in children {
                    if viewNames.contains(child) {
                        relatedViews.insert(viewName)
                        relatedViews.insert(child)
                    }
                }
            }
            
            // Check if this view is a child of any other view that has the same state variable
            for (parent, children) in parentChildRelationships {
                if children.contains(viewName) && viewNames.contains(parent) {
                    relatedViews.insert(viewName)
                    relatedViews.insert(parent)
                }
            }
        }
        
        return Array(relatedViews)
    }
    
    /// Finds views related through navigation relationships (not parent-child)
    func findNavigationRelatedViews(for variables: [StateVariableInfo]) -> [String] {
        let viewNames = Set(variables.map { $0.viewName })
        var relatedViews: Set<String> = []
        
        // Check for navigation relationships
        for viewName in viewNames {
            // Check if this view has navigation destinations that also have the same state variable
            if let children = navigationRelationships[viewName] {
                for child in children {
                    if viewNames.contains(child) {
                        relatedViews.insert(viewName)
                        relatedViews.insert(child)
                    }
                }
            }
            
            // Check if this view is a navigation destination of any other view that has the same state variable
            for (parent, children) in navigationRelationships {
                if children.contains(viewName) && viewNames.contains(parent) {
                    relatedViews.insert(viewName)
                    relatedViews.insert(parent)
                }
            }
        }
        
        return Array(relatedViews)
    }
    
    /// Finds views related through modal relationships
    func findModalRelatedViews(for variables: [StateVariableInfo]) -> [String] {
        let viewNames = Set(variables.map { $0.viewName })
        var relatedViews: Set<String> = []
        
        // Check for modal relationships
        for viewName in viewNames {
            // Check if this view has modal presentations that also have the same state variable
            if let children = modalRelationships[viewName] {
                for child in children {
                    if viewNames.contains(child) {
                        relatedViews.insert(viewName)
                        relatedViews.insert(child)
                    }
                }
            }
            
            // Check if this view is a modal presentation of any other view that has the same state variable
            for (parent, children) in modalRelationships {
                if children.contains(viewName) && viewNames.contains(parent) {
                    relatedViews.insert(viewName)
                    relatedViews.insert(parent)
                }
            }
        }
        
        return Array(relatedViews)
    }
}

// MARK: - View Name Extractor Visitor

/// A visitor that extracts SwiftUI view names from a source file
class ViewNameExtractorVisitor: SyntaxVisitor {
    var viewNames: [String] = []
    
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check if this is a SwiftUI view
        if isSwiftUIView(node) {
            viewNames.append(node.name.text)
        }
        return .visitChildren
    }
    
    private func isSwiftUIView(_ node: StructDeclSyntax) -> Bool {
        // Check if the struct conforms to View protocol
        for inheritance in node.inheritanceClause?.inheritedTypes ?? [] {
            if inheritance.type.as(IdentifierTypeSyntax.self)?.name.text == "View" {
                return true
            }
        }
        return false
    }
} 
