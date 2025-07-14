/// Registry for managing SwiftSyntax-based pattern visitors and their configurations.
///
/// `PatternVisitorRegistry` provides a centralized way to register, retrieve, and
/// manage pattern visitors for different categories of code analysis. It supports
/// dynamic pattern registration and category-based visitor retrieval.
///
/// - Note: This registry is designed to be thread-safe and supports concurrent access.
@MainActor
public class PatternVisitorRegistry {
    public static let shared = PatternVisitorRegistry()
    
    private var patterns: [SyntaxPattern] = []
    private var visitorsByCategory: [PatternCategory: [PatternVisitor.Type]] = [:]
    private let queue = DispatchQueue(label: "PatternVisitorRegistry", attributes: .concurrent)
    
    public init() {}
    
    /// Registers a new syntax pattern with the registry.
    ///
    /// - Parameter pattern: The syntax pattern to register.
    func register(pattern: SyntaxPattern) {
        queue.sync(flags: .barrier) {
            self.patterns.append(pattern)
            if self.visitorsByCategory[pattern.category] == nil {
                self.visitorsByCategory[pattern.category] = []
            }
            self.visitorsByCategory[pattern.category]?.append(pattern.visitor)
        }
    }
    
    /// Registers multiple syntax patterns at once.
    ///
    /// - Parameter patterns: An array of syntax patterns to register.
    func register(patterns: [SyntaxPattern]) {
        queue.sync(flags: .barrier) {
            for pattern in patterns {
                self.patterns.append(pattern)
                if self.visitorsByCategory[pattern.category] == nil {
                    self.visitorsByCategory[pattern.category] = []
                }
                self.visitorsByCategory[pattern.category]?.append(pattern.visitor)
            }
        }
    }
    
    /// Retrieves all visitor types for a specific pattern category.
    ///
    /// - Parameter category: The pattern category to retrieve visitors for.
    /// - Returns: An array of visitor types for the specified category.
    func getVisitors(for category: PatternCategory) -> [PatternVisitor.Type] {
        return queue.sync {
            let visitors = visitorsByCategory[category] ?? []
            print("DEBUG: Registry.getVisitors(for: \(category)) returning \(visitors.count) visitors")
            print("DEBUG: Available categories in registry: \(visitorsByCategory.keys.map { $0 })")
            return visitors
        }
    }
    
    /// Retrieves all registered visitor types.
    ///
    /// - Returns: An array of all registered visitor types.
    func getAllVisitors() -> [PatternVisitor.Type] {
        return queue.sync {
            return patterns.map { $0.visitor }
        }
    }
    
    /// Retrieves all registered syntax patterns.
    ///
    /// - Returns: An array of all registered syntax patterns.
    func getAllPatterns() -> [SyntaxPattern] {
        return queue.sync {
            return patterns
        }
    }
    
    /// Retrieves syntax patterns for a specific category.
    ///
    /// - Parameter category: The pattern category to retrieve patterns for.
    /// - Returns: An array of syntax patterns for the specified category.
    func getPatterns(for category: PatternCategory) -> [SyntaxPattern] {
        return queue.sync {
            return patterns.filter { $0.category == category }
        }
    }
    
    /// Clears all registered patterns and visitors.
    func clear() {
        queue.sync(flags: .barrier) {
            self.patterns.removeAll()
            self.visitorsByCategory.removeAll()
        }
    }
}