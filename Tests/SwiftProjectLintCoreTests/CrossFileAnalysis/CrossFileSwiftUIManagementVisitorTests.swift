import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

@Suite("CrossFileSwiftUIManagementVisitorTests")
struct CrossFileSwiftUIManagementVisitorTests {
    
    @Test func testInitializationWithFileCache() {
        let source1 = "struct View1: View { var body: some View { Text(\"1\") } }"
        let source2 = "struct View2: View { var body: some View { Text(\"2\") } }"
        
        let file1 = Parser.parse(source: source1)
        let file2 = Parser.parse(source: source2)
        
        let fileCache: [String: SourceFileSyntax] = [
            "View1.swift": file1,
            "View2.swift": file2
        ]
        
        let visitor = CrossFileSwiftUIManagementVisitor(fileCache: fileCache)
        
        #expect(visitor.fileCache.count == 2)
        #expect(visitor.fileCache["View1.swift"] != nil)
        #expect(visitor.fileCache["View2.swift"] != nil)
    }
    
    @Test func testInitializationWithEmptyFileCache() {
        let visitor = CrossFileSwiftUIManagementVisitor(fileCache: [:])
        
        #expect(visitor.fileCache.isEmpty)
    }
    
    @Test func testInitializationWithPatternCategory() {
        // The patternCategory initializer creates an empty file cache
        let visitor = CrossFileSwiftUIManagementVisitor(patternCategory: .stateManagement)
        
        #expect(visitor.fileCache.isEmpty)
    }
    
    @Test func testInitializationWithViewMode() {
        let visitor = CrossFileSwiftUIManagementVisitor(viewMode: .sourceAccurate)
        
        #expect(visitor.fileCache.isEmpty)
    }
    
    @Test func testFinalizeAnalysis() {
        let fileCache: [String: SourceFileSyntax] = [:]
        let visitor = CrossFileSwiftUIManagementVisitor(fileCache: fileCache)
        
        // Should not crash
        visitor.finalizeAnalysis()
    }
    
    @Test func testAcceptVisitor() throws {
        let source = "struct View1: View { var body: some View { Text(\"1\") } }"
        let file = Parser.parse(source: source)
        let fileCache: [String: SourceFileSyntax] = ["View1.swift": file]
        
        let crossFileVisitor = CrossFileSwiftUIManagementVisitor(fileCache: fileCache)
        
        // Create a simple visitor to test accept
        class TestVisitor: SyntaxVisitor, PatternVisitorProtocol {
            var visitCount = 0
            var detectedIssues: [LintIssue] = []
            static var type: VisitorType { .architecture }
            var patternCategory: PatternCategory { .architecture }
            
            required override init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
                super.init(viewMode: viewMode)
            }
            
            required init(patternCategory: PatternCategory) {
                super.init(viewMode: .sourceAccurate)
            }
            
            func reset() {
                detectedIssues.removeAll()
                visitCount = 0
            }
            
            override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
                visitCount += 1
                return .visitChildren
            }
        }
        
        let testVisitor = TestVisitor()
        try crossFileVisitor.accept(visitor: testVisitor)
        
        // The accept method should walk all files in the cache
        #expect(testVisitor.visitCount >= 1)
    }
    
    @Test func testFileCacheIsPreserved() {
        let source1 = "struct View1: View { var body: some View { Text(\"1\") } }"
        let source2 = "struct View2: View { var body: some View { Text(\"2\") } }"
        let source3 = "struct View3: View { var body: some View { Text(\"3\") } }"
        
        let file1 = Parser.parse(source: source1)
        let file2 = Parser.parse(source: source2)
        let file3 = Parser.parse(source: source3)
        
        let fileCache: [String: SourceFileSyntax] = [
            "View1.swift": file1,
            "View2.swift": file2,
            "View3.swift": file3
        ]
        
        let visitor = CrossFileSwiftUIManagementVisitor(fileCache: fileCache)
        
        #expect(visitor.fileCache.count == 3)
        #expect(visitor.fileCache.keys.contains("View1.swift"))
        #expect(visitor.fileCache.keys.contains("View2.swift"))
        #expect(visitor.fileCache.keys.contains("View3.swift"))
    }
}
