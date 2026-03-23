import Foundation

/// Represents a Swift source file in a project, with its name and contents.
public struct ProjectFile: Sendable, Equatable {
    public let name: String
    public let content: String
    
    public init(name: String, content: String) {
        self.name = name
        self.content = content
    }
} 
