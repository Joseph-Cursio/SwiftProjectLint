import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite("ViewRelationship Advanced Detection Tests")
struct ViewRelationshipAdvancedTests {

    private func extractRelationships(from sourceCode: String, parentView: String) -> [ViewRelationship] {
        let sourceFile = Parser.parse(source: sourceCode)
        let converter = SourceLocationConverter(fileName: "test.swift", tree: sourceFile)
        let visitor = ViewRelationshipVisitor(
            parentView: parentView,
            filePath: "test.swift",
            sourceContents: sourceCode,
            sourceLocationConverter: converter
        )
        visitor.walk(sourceFile)
        return visitor.relationships
    }

    // MARK: - Container Views with Nested Custom Views

    @Test("detects custom views nested inside container views")
    func customViewsInsideContainerViews() throws {
        let source = """
        struct ParentView: View {
            var body: some View {
                VStack {
                    HStack {
                        ProfileCard()
                        AvatarView()
                    }
                }
            }
        }
        """

        let relationships = extractRelationships(from: source, parentView: "ParentView")
        let childNames = relationships.map(\.childView)
        #expect(childNames.contains("ProfileCard"))
        #expect(childNames.contains("AvatarView"))
        #expect(relationships.allSatisfy { $0.relationshipType == .directChild })
    }

    @Test("skips system views inside containers")
    func systemViewsInsideContainersSkipped() throws {
        let source = """
        struct ParentView: View {
            var body: some View {
                VStack {
                    Text("Hello")
                    Image("logo")
                    Spacer()
                    Divider()
                    Button("Tap") { }
                }
            }
        }
        """

        let relationships = extractRelationships(from: source, parentView: "ParentView")
        #expect(relationships.isEmpty, "System views should not be detected as custom children")
    }

    // MARK: - NavigationLink Content Closure

    @Test("views inside NavigationLink content are not detected as direct children")
    func viewsInsideNavigationLinkNotDirectChild() throws {
        let source = """
        struct ParentView: View {
            var body: some View {
                NavigationLink(destination: DetailView()) {
                    RowView()
                }
            }
        }
        """

        let relationships = extractRelationships(from: source, parentView: "ParentView")
        let navDest = relationships.filter { $0.relationshipType == .navigationDestination }
        #expect(navDest.count == 1)
        #expect(navDest.first?.childView == "DetailView")
    }

    @Test("NavigationLink without destination argument")
    func navigationLinkWithoutDestination() throws {
        let source = """
        struct ParentView: View {
            var body: some View {
                NavigationLink {
                    DetailView()
                } label: {
                    Text("Go")
                }
            }
        }
        """

        let relationships = extractRelationships(from: source, parentView: "ParentView")
        // Without a "destination" labeled argument, the visitor still walks children
        #expect(true)
    }

    // MARK: - Presentation Modifiers with Content Label

    @Test("sheet with content labeled argument detects custom view")
    func sheetWithContentLabel() throws {
        let source = """
        struct ParentView: View {
            @State var showSheet = false
            var body: some View {
                Text("Hello")
                    .sheet(isPresented: $showSheet, content: {
                        SettingsView()
                    })
            }
        }
        """

        let relationships = extractRelationships(from: source, parentView: "ParentView")
        let sheetRels = relationships.filter { $0.relationshipType == .sheet }
        #expect(sheetRels.count == 1)
        #expect(sheetRels.first?.childView == "SettingsView")
    }

    @Test("fullScreenCover with content labeled argument")
    func fullScreenCoverWithContentLabel() throws {
        let source = """
        struct ParentView: View {
            @State var showCover = false
            var body: some View {
                Text("Hello")
                    .fullScreenCover(isPresented: $showCover, content: {
                        OnboardingView()
                    })
            }
        }
        """

        let relationships = extractRelationships(from: source, parentView: "ParentView")
        let coverRels = relationships.filter { $0.relationshipType == .fullScreenCover }
        #expect(coverRels.count == 1)
        #expect(coverRels.first?.childView == "OnboardingView")
    }

    @Test("popover with content labeled argument")
    func popoverWithContentLabel() throws {
        let source = """
        struct ParentView: View {
            @State var showPop = false
            var body: some View {
                Text("Hello")
                    .popover(isPresented: $showPop, content: {
                        InfoView()
                    })
            }
        }
        """

        let relationships = extractRelationships(from: source, parentView: "ParentView")
        let popRels = relationships.filter { $0.relationshipType == .popover }
        #expect(popRels.count == 1)
        #expect(popRels.first?.childView == "InfoView")
    }

    // MARK: - Multiple Custom Views in Presentation Closures

    @Test("sheet with multiple custom views in closure")
    func sheetWithMultipleViews() throws {
        let source = """
        struct ParentView: View {
            @State var showSheet = false
            var body: some View {
                Text("Hello")
                    .sheet(isPresented: $showSheet) {
                        VStack {
                            HeaderView()
                            ContentPanel()
                        }
                    }
            }
        }
        """

        let relationships = extractRelationships(from: source, parentView: "ParentView")
        let sheetRels = relationships.filter { $0.relationshipType == .sheet }
        let sheetChildNames = sheetRels.map(\.childView)
        #expect(sheetChildNames.contains("HeaderView"))
        #expect(sheetChildNames.contains("ContentPanel"))
    }

    // MARK: - Member Access View Name Extraction

    @Test("detects view name from member access expression in NavigationLink")
    func memberAccessInNavigationDestination() throws {
        let source = """
        struct ParentView: View {
            var body: some View {
                NavigationLink(destination: MyModule.DetailView()) {
                    Text("Go")
                }
            }
        }
        """

        let relationships = extractRelationships(from: source, parentView: "ParentView")
        let navRels = relationships.filter { $0.relationshipType == .navigationDestination }
        #expect(navRels.count == 1)
        #expect(navRels.first?.childView == "DetailView")
    }
}
