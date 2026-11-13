import Foundation
import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Related Duplicate State Variable at the visitor: which parent/child pairs it relates, and where it
/// reports. The end-to-end runs through `ProjectLinter` are in `RelatedDuplicateStateProjectTests`.
@Suite
struct RelatedDuplicateStateVisitorTests {

    private func issues(_ files: [String: String]) -> [LintIssue] {
        CrossFileVisitorTestSupport.issues(
            of: RelatedDuplicateStateVisitor.self,
            pattern: RelatedDuplicateStateVariable().pattern,
            files: files
        )
    }

    private static let parent = """
    import SwiftUI
    struct ParentView: View {
        @State private var isLoggedIn = false
        var body: some View {
            ChildView()
        }
    }
    """

    private static let child = """
    import SwiftUI
    struct ChildView: View {
        @State private var isLoggedIn = false
        var body: some View {
            Text(isLoggedIn ? "In" : "Out")
        }
    }
    """

    // MARK: - Reported

    @Test("a parent and the child it shows, in one file, report at the child's declaration")
    func reportsParentAndChildInOneFile() throws {
        let found = issues(["Views.swift": Self.parent + "\n" + Self.child])
        let issue = try #require(found.first)
        #expect(found.count == 1)
        #expect(issue.filePath == "Views.swift")
        #expect(issue.lineNumber == 10)
        #expect(issue.message.contains("'isLoggedIn' is @State in ChildView and in its parent ParentView"))
        #expect(issue.suggestion?.contains("@Binding var isLoggedIn") == true)
    }

    @Test("split across two files, the report lands in the child's file, whatever the walk order")
    func reportsAcrossFilesAtTheChild() throws {
        let files = ["ParentView.swift": Self.parent, "ChildView.swift": Self.child]
        let found = issues(files)
        let issue = try #require(found.first)
        #expect(found.count == 1)
        #expect(issue.filePath == "ChildView.swift")
        #expect(issue.lineNumber == 3)
    }

    @Test("a child shown from a sheet, a NavigationLink, a helper property or an extension counts")
    func reportsEveryWayAParentShowsAChild() {
        // Each shape is the whole of ParentView's members after its state, and only one of them
        // constructs the child.
        let shapes: [String: String] = [
            "sheet": "var body: some View { Text(\"x\").sheet(isPresented: .constant(true)) { ChildView() } }",
            "navigationLink": "var body: some View { NavigationLink(destination: ChildView()) { Text(\"Go\") } }",
            "helper": "var body: some View { header }\n    var header: some View { ChildView() }",
        ]
        for (label, members) in shapes {
            let parent = """
            import SwiftUI
            struct ParentView: View {
                @State private var isLoggedIn = false
                \(members)
            }
            """
            #expect(issues(["P.swift": parent, "C.swift": Self.child]).count == 1, "shape: \(label)")
        }

        let viaExtension = """
        import SwiftUI
        struct ParentView: View {
            @State private var isLoggedIn = false
            var body: some View { footer }
        }
        extension ParentView {
            var footer: some View { ChildView() }
        }
        """
        #expect(issues(["P.swift": viaExtension, "C.swift": Self.child]).count == 1)
    }

    @Test("an attribute on its own line puts the report on the attribute's line, where disable:next aims")
    func reportsOnTheDeclarationsFirstLine() throws {
        let child = Self.child.replacingOccurrences(
            of: "    @State private var isLoggedIn = false", with: "    @State\n    private var isLoggedIn = false"
        )
        let found = issues(["P.swift": Self.parent, "C.swift": child])
        #expect(try #require(found.first).lineNumber == 3)
    }

    @Test("a child that is a view by extension, by `SwiftUI.View`, or built as `Row<Int>(…)` counts")
    func reportsEveryWayAStructBecomesAChild() {
        let parent = """
        struct ParentView: View {
            @State private var isOn = false
            @State private var count = 0
            @State private var selection = 0
            var body: some View { ChildA(); ChildB(); Row<Int>(value: 1) }
        }
        """
        let children = """
        struct ChildA { @State private var isOn = false }
        extension ChildA: View { var body: some View { Text("") } }
        struct ChildB: SwiftUI.View {
            @State private var count = 0
            var body: some View { Text("") }
        }
        struct Row<T>: View {
            let value: T
            @State private var selection = 0
            var body: some View { Text("") }
        }
        """
        let found = issues(["P.swift": parent, "C.swift": children])
        #expect(found.map { $0.message.components(separatedBy: "'")[1] }.sorted() == ["count", "isOn", "selection"])
    }

    @Test("an App struct is a parent of the view its scene builds")
    func appIsAParent() {
        let app = """
        @main struct DemoApp: App {
            @State private var isLoggedIn = false
            var body: some Scene { WindowGroup { ChildView() } }
        }
        """
        let found = issues(["App.swift": app, "C.swift": Self.child])
        #expect(found.count == 1)
        #expect(found.first?.message.contains("its parent DemoApp") == true)
    }

    @Test("a parent owning the name with another wrapper is named with that wrapper")
    func differentWrappersAreNamed() throws {
        let parent = """
        struct ParentView: View {
            @StateObject private var model = Model()
            var body: some View { ChildView() }
        }
        """
        let child = """
        struct ChildView: View {
            @State private var model = Model()
            var body: some View { Text("") }
        }
        """
        let issue = try #require(issues(["P.swift": parent, "C.swift": child]).first)
        #expect(issue.message.contains("'model' is @State in ChildView and in its parent ParentView (as @StateObject)"))
    }

    @Test("@StateObject pairs count, and a qualified @SwiftUI.State is still @State")
    func reportsStateObjectAndQualifiedState() {
        let parent = """
        struct ParentView: View {
            @StateObject var model = Model()
            @SwiftUI.State var count = 0
            var body: some View { ChildView() }
        }
        """
        let child = """
        struct ChildView: View {
            @StateObject var model = Model()
            @State var count = 0
            var body: some View { Text("") }
        }
        """
        let found = issues(["P.swift": parent, "C.swift": child])
        #expect(found.count == 2)
        #expect(found.contains { $0.message.contains("'model' is @StateObject") })
        #expect(found.contains { $0.message.contains("'count' is @State") })
    }

    @Test("a child shown by two parents is reported once, naming both")
    func oneReportPerChildDeclaration() throws {
        let second = Self.parent.replacingOccurrences(of: "ParentView", with: "OtherParent")
        let found = issues(["A.swift": Self.parent, "B.swift": second, "C.swift": Self.child])
        let issue = try #require(found.first)
        #expect(found.count == 1)
        #expect(issue.message.contains("its parents OtherParent, ParentView"))
    }

    // MARK: - Not reported

    @Test("a child that takes @Binding is the fix, not a finding")
    func bindingChildIsClean() {
        let child = Self.child.replacingOccurrences(
            of: "@State private var isLoggedIn = false", with: "@Binding var isLoggedIn: Bool"
        )
        #expect(issues(["P.swift": Self.parent, "C.swift": child]).isEmpty)
    }

    @Test("two views that never show one another are left alone")
    func unrelatedViewsAreClean() {
        let parent = Self.parent.replacingOccurrences(of: "ChildView()", with: "Text(\"no child\")")
        #expect(issues(["P.swift": parent, "C.swift": Self.child]).isEmpty)
    }

    @Test("a grandchild is not compared with its grandparent")
    func onlyDirectPairsCount() {
        let parent = Self.parent.replacingOccurrences(of: "ChildView()", with: "MiddleView()")
        let middle = """
        struct MiddleView: View {
            var body: some View { ChildView() }
        }
        """
        #expect(issues(["P.swift": parent, "M.swift": middle, "C.swift": Self.child]).isEmpty)
    }

    @Test("written types that differ keep two same-named properties apart")
    func differentWrittenTypesAreClean() {
        let parent = Self.parent.replacingOccurrences(
            of: "@State private var isLoggedIn = false", with: "@State private var isLoggedIn: Bool = false"
        )
        let child = Self.child.replacingOccurrences(
            of: "@State private var isLoggedIn = false", with: "@State private var isLoggedIn: String = \"\""
        )
        #expect(issues(["P.swift": parent, "C.swift": child]).isEmpty)
    }

    @Test("a view name declared twice is ambiguous and takes part in no pair")
    func ambiguousViewNamesAreSkipped() {
        let duplicateChild = Self.child.replacingOccurrences(of: "Text(isLoggedIn ? \"In\" : \"Out\")", with: "EmptyView()")
        #expect(issues(["P.swift": Self.parent, "C.swift": Self.child, "D.swift": duplicateChild]).isEmpty)
    }

    @Test("a view that shows itself, and state that is not @State or @StateObject, are not pairs")
    func selfReferenceAndOtherWrappersAreClean() {
        let recursive = """
        struct TreeView: View {
            @State private var expanded = false
            var body: some View { TreeView() }
        }
        """
        #expect(issues(["T.swift": recursive]).isEmpty)

        let parent = """
        struct ParentView: View {
            @Environment(\\.dismiss) var dismiss
            @AppStorage("name") var name = ""
            var body: some View { ChildView() }
        }
        """
        let child = """
        struct ChildView: View {
            @Environment(\\.dismiss) var dismiss
            @AppStorage("name") var name = ""
            var body: some View { Text("") }
        }
        """
        #expect(issues(["P.swift": parent, "C.swift": child]).isEmpty)
    }

    @Test("a #Preview, a non-view type owning the same @State, or a non-view type nested in the parent adds no pair")
    func previewsAndNonViewTypesAddNoEdges() {
        let parent = Self.parent.replacingOccurrences(of: "ChildView()", with: "Text(\"\")")
        let preview = "#Preview { ParentView() ; ChildView() }"
        #expect(issues(["P.swift": parent, "C.swift": Self.child, "Preview.swift": preview]).isEmpty)

        // A struct that is not a view, yet owns the same @State and builds the child.
        let factory = """
        struct Factory {
            @State private var isLoggedIn = false
            func make() -> some View { ChildView() }
        }
        """
        #expect(issues(["P.swift": parent, "C.swift": Self.child, "F.swift": factory]).isEmpty)

        // The child built by a non-view type nested inside a parent that owns the same @State.
        let nesting = """
        struct ParentView: View {
            @State private var isLoggedIn = false
            var body: some View { Builder.make() }
            enum Builder { static func make() -> some View { ChildView() } }
        }
        """
        #expect(issues(["P.swift": nesting, "C.swift": Self.child]).isEmpty)
    }

    @Test("a nested view answers only calls inside its enclosing type, not a system view or model of its name")
    func nestedViewsDoNotCaptureOutsideCalls() {
        let screen = """
        struct SettingsScreen: View {
            var body: some View { Label() }
            private struct Label: View {
                @State private var isExpanded = false
                var body: some View { Text("") }
            }
        }
        """
        let profile = """
        struct ProfileView: View {
            @State private var isExpanded = false
            var body: some View { Label("Profile", systemImage: "person") }
        }
        """
        #expect(issues(["A.swift": screen, "B.swift": profile]).isEmpty)

        // The enclosing type itself does show its nested view.
        let owning = screen.replacingOccurrences(
            of: "struct SettingsScreen: View {", with: "struct SettingsScreen: View {\n    @State private var isExpanded = false"
        )
        #expect(issues(["A.swift": owning]).count == 1)

        let models = """
        struct Cell { var id = 0 }
        struct ListScreen: View {
            var body: some View { Text("") }
            struct Cell: View {
                @State private var isExpanded = false
                var body: some View { Text("") }
            }
        }
        struct DetailView: View {
            @State private var isExpanded = false
            let cells = [Cell(id: 1)]
            var body: some View { Text("") }
        }
        """
        #expect(issues(["M.swift": models]).isEmpty)
    }

    // MARK: - Determinism

    @Test("the same issues come out whatever order the files are walked in")
    func resultDoesNotDependOnWalkOrder() {
        let second = Self.parent.replacingOccurrences(of: "ParentView", with: "OtherParent")
        let files = ["A.swift": Self.parent, "B.swift": second, "C.swift": Self.child]
        var signatures: Set<[String]> = []
        for order in WalkOrders.of(Array(files.keys)) {
            var cache: [String: SourceFileSyntax] = [:]
            for (name, source) in files { cache[name] = Parser.parse(source: source) }
            let visitor = RelatedDuplicateStateVisitor(fileCache: cache)
            visitor.setPattern(RelatedDuplicateStateVariable().pattern)
            for name in order {
                guard let tree = cache[name] else { continue }
                visitor.setFilePath(name)
                visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: tree))
                visitor.walk(tree)
            }
            visitor.finalizeAnalysis()
            signatures.insert(WalkOrders.signature(of: visitor.detectedIssues))
        }
        #expect(signatures.count == 1)
        #expect(signatures.first?.count == 1)
    }
}
