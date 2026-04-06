import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite("ViewRelationship Edge Case Tests")
struct ViewRelationshipEdgeCaseTests {

    private func extractRelationships(from sourceCode: String, parentView: String) -> [ViewRelationship] {
        let sourceFile = Parser.parse(source: sourceCode)
        let converter = SourceLocationConverter(fileName: "test.swift", tree: sourceFile)
        let visitor = ViewRelationshipVisitor(
            parentView: parentView,
            filePath: "test.swift",
            sourceLocationConverter: converter
        )
        visitor.walk(sourceFile)
        return visitor.relationships
    }

    // MARK: - Struct Declaration Visiting

    @Test("visits struct declarations without issues")
    func visitsStructDeclarations() throws {
        let source = """
        struct ContentView: View {
            var body: some View {
                CustomChild()
            }
        }
        struct HelperView: View {
            var body: some View {
                Text("Helper")
            }
        }
        """

        let relationships = extractRelationships(from: source, parentView: "ContentView")
        let directChildren = relationships.filter { $0.relationshipType == .directChild }
        #expect(directChildren.count == 1)
        #expect(directChildren.first?.childView == "CustomChild")
    }

    // MARK: - Unknown Modifier Does Not Create Relationship

    @Test("unknown modifier does not create presentation relationship")
    func unknownModifierIgnored() throws {
        let source = """
        struct ParentView: View {
            var body: some View {
                Text("Hello")
                    .onTapGesture {
                        CustomView()
                    }
            }
        }
        """

        let relationships = extractRelationships(from: source, parentView: "ParentView")
        let presentationRels = relationships.filter {
            $0.relationshipType == .sheet ||
            $0.relationshipType == .popover ||
            $0.relationshipType == .alert ||
            $0.relationshipType == .fullScreenCover
        }
        #expect(presentationRels.isEmpty)
    }

    // MARK: - Direct Child Not Detected When Already Special

    @Test("view detected in sheet is not also detected as direct child")
    func sheetViewNotDuplicatedAsDirectChild() throws {
        let source = """
        struct ParentView: View {
            @State var showSheet = false
            var body: some View {
                Button("Show") { showSheet = true }
                    .sheet(isPresented: $showSheet) {
                        SettingsView()
                    }
            }
        }
        """

        let relationships = extractRelationships(from: source, parentView: "ParentView")
        let settingsRels = relationships.filter { $0.childView == "SettingsView" }
        #expect(settingsRels.count == 1)
        #expect(settingsRels.first?.relationshipType == .sheet)
    }

    // MARK: - Empty Source and Edge Cases

    @Test("empty source produces no relationships")
    func emptySourceNoRelationships() throws {
        let relationships = extractRelationships(from: "", parentView: "EmptyView")
        #expect(relationships.isEmpty)
    }

    @Test("source with no views produces no relationships")
    func noViewsNoRelationships() throws {
        let source = """
        let value = 42
        func compute() -> Int { return value * 2 }
        """

        let relationships = extractRelationships(from: source, parentView: "SomeView")
        #expect(relationships.isEmpty)
    }

    @Test("deeply nested containers detect custom views at all levels")
    func deeplyNestedContainers() throws {
        let source = """
        struct DeepView: View {
            var body: some View {
                ScrollView {
                    VStack {
                        HStack {
                            Group {
                                DeepChild()
                            }
                        }
                    }
                }
            }
        }
        """

        let relationships = extractRelationships(from: source, parentView: "DeepView")
        let directChildren = relationships.filter { $0.relationshipType == .directChild }
        #expect(directChildren.count == 1)
        #expect(directChildren.first?.childView == "DeepChild")
    }

    // MARK: - Relationship Metadata

    @Test("relationship contains correct parent view name")
    func relationshipHasCorrectParent() throws {
        let source = """
        struct RootView: View {
            var body: some View {
                ChildWidget()
            }
        }
        """

        let relationships = extractRelationships(from: source, parentView: "RootView")
        let child = try #require(relationships.first)
        #expect(child.parentView == "RootView")
        #expect(child.childView == "ChildWidget")
        #expect(child.filePath == "test.swift")
        #expect(child.lineNumber > 0)
    }

    @Test("alert relationship type is detected correctly")
    func alertRelationshipType() throws {
        let source = """
        struct AlertHost: View {
            @State var showAlert = false
            var body: some View {
                Text("Hello")
                    .alert("Title", isPresented: $showAlert) {
                        CustomAlertContent()
                    }
            }
        }
        """

        let relationships = extractRelationships(from: source, parentView: "AlertHost")
        let alertRels = relationships.filter { $0.relationshipType == .alert }
        #expect(alertRels.count == 1)
        #expect(alertRels.first?.childView == "CustomAlertContent")
    }

    // MARK: - Multiple Direct Children

    @Test("detects multiple custom direct children in flat layout")
    func multipleDirectChildrenFlat() throws {
        let source = """
        struct DashboardView: View {
            var body: some View {
                VStack {
                    HeaderSection()
                    StatsPanel()
                    ActionBar()
                }
            }
        }
        """

        let relationships = extractRelationships(from: source, parentView: "DashboardView")
        let childNames = Set(relationships.map(\.childView))
        #expect(childNames.contains("HeaderSection"))
        #expect(childNames.contains("StatsPanel"))
        #expect(childNames.contains("ActionBar"))
        #expect(relationships.count == 3)
    }

    // MARK: - List and Section Container Views

    @Test("detects custom views inside List container")
    func customViewsInsideList() throws {
        let source = """
        struct ListView: View {
            var body: some View {
                List {
                    Section {
                        RowItem()
                    }
                }
            }
        }
        """

        let relationships = extractRelationships(from: source, parentView: "ListView")
        let directChildren = relationships.filter { $0.relationshipType == .directChild }
        #expect(directChildren.count == 1)
        #expect(directChildren.first?.childView == "RowItem")
    }

    @Test("detects custom views inside Form container")
    func customViewsInsideForm() throws {
        let source = """
        struct FormView: View {
            var body: some View {
                Form {
                    SettingsRow()
                }
            }
        }
        """

        let relationships = extractRelationships(from: source, parentView: "FormView")
        let directChildren = relationships.filter { $0.relationshipType == .directChild }
        #expect(directChildren.count == 1)
        #expect(directChildren.first?.childView == "SettingsRow")
    }
}
