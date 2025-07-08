import Foundation
import SwiftSyntax
import SwiftParser

// Simple test to see debug output
let source = """
let url = URL(string: "https://example.com")!
let data = try Data(contentsOf: url)
"""

print("Testing source code:")
print(source)
print("---")

let syntax = Parser.parse(source: source)
print("Parsed syntax tree:")
print(syntax.description)
print("---")

// Create visitor and walk the tree
let visitor = NetworkingVisitor(patternCategory: .networking)
visitor.walk(syntax)

print("Detected issues: \(visitor.detectedIssues.count)")
for (index, issue) in visitor.detectedIssues.enumerated() {
    print("Issue \(index + 1):")
    print("  Message: \(issue.message)")
    print("  Severity: \(issue.severity)")
    print("  Line: \(issue.lineNumber)")
} 