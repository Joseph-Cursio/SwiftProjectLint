@testable import Core
import Testing

/// Where a name used in a chain was bound, and where it was not: the scopes a second review
/// round found the resolver reading wrongly, plus the slot and ownership cases it raised.
@Suite
struct PositionalViewLookupBindingTests {

    private func analyze(_ body: String) -> [LintIssue] {
        positionalViewLookupIssues(in: body)
    }

    private func analyzeTest(_ statements: String) -> [LintIssue] {
        positionalViewLookupIssues(inTestBody: statements)
    }

    // MARK: - Slots and items

    @Test("a slot's content may be several views, so x(0) on it picks the first")
    func slotContent() {
        let issues = analyzeTest("""
            _ = try sut.inspect().find(ViewType.Button.self).labelView().image(0)
            _ = try sut.inspect().find(ViewType.Button.self).labelView().text().string()
            _ = try sut.inspect().overlay().view(BadgeView.self).text()
        """)
        #expect(issues.map(\.lineNumber) == [5])
    }

    @Test("a toolbar item holds its views in order; bar items index the container")
    func itemsInOrder() {
        let issues = analyzeTest("""
            let item = try sut.inspect().toolbar().item(0)
            _ = try item.text(0).string()
            _ = try sut.inspect().navigationView().navigationBarItems(0)
        """)
        #expect(issues.map(\.lineNumber) == [6, 7])
    }

    @Test("climbing out of a test-declared view into the app's layout is reported")
    func parentLeavesOwnedView() {
        let issues = analyze("""
        private struct OwnedRow: View { var body: some View { Text("row") } }

        func testClimb(app: AppScreen) throws {
            let row = try app.inspect().find(OwnedRow.self)
            _ = try row.parent().parent()
        }
        """)
        #expect(issues.map(\.lineNumber) == [7])
    }

    @Test("entering an app view from a test-declared host starts the count over")
    func enteringAppLayout() {
        let issues = analyze("""
        private struct OwnedHost: View { var body: some View { VStack { AppRow() } } }

        func testHost() throws {
            _ = try OwnedHost().inspect().vStack().view(AppRow.self).vStack()
            _ = try OwnedHost().inspect().vStack().view(AppRow.self).vStack().hStack(1)
        }
        """)
        #expect(issues.map(\.lineNumber) == [7])
    }

    // MARK: - Type members

    @Test("an extension of the test class sees the properties the class declares")
    func extensionSeesClassProperties() {
        let issues = analyze("""
        final class SplitTests: XCTestCase {
            var stack: InspectableView<ViewType.VStack>!
        }

        extension SplitTests {
            func helper() throws {
                _ = try stack.text(2)
                _ = try self.stack.text(3)
            }
        }
        """)
        #expect(issues.map(\.lineNumber) == [9, 10])
    }

    @Test("Self.x and Type.x read a static property")
    func staticProperty() {
        let issues = analyze("""
        final class MemberKindTests: XCTestCase {
            static let shared = try! AppView().inspect().find(ViewType.VStack.self)

            func testStatic() throws {
                _ = try Self.shared.hStack(1)
                _ = try MemberKindTests.shared.hStack(2)
            }
        }
        """)
        #expect(issues.map(\.lineNumber) == [7, 8])
    }

    @Test("self.x inside a member #if block reads the class's property")
    func selfInsideMemberIfConfig() {
        let issues = analyze("""
        final class ConfigTests: XCTestCase {
            var stack: InspectableView<ViewType.VStack>!

            #if os(iOS)
            func testInside() throws {
                _ = try self.stack.hStack(1)
            }
            #endif
        }
        """)
        #expect(issues.map(\.lineNumber) == [8])
    }

    @Test("a file-scope value declared below the tests is visible to them")
    func lateGlobal() {
        let issues = analyze("""
        func testLate() throws {
            _ = try lateRoot.hStack(2)
        }

        let lateRoot = try! AppView().inspect().find(ViewType.VStack.self)
        """)
        #expect(issues.map(\.lineNumber) == [4])
    }

    // MARK: - Declarations

    @Test("the first #if branch is the configuration read")
    func firstIfConfigBranch() {
        let issues = analyzeTest("""
            #if canImport(UIKit)
            let stack = try sut.inspect().find(ViewType.VStack.self)
            #else
            let stack = Wrapper()
            #endif
            _ = try stack.text(4)
        """)
        #expect(issues.map(\.lineNumber) == [10])
    }

    @Test("annotations shared, conditional, optional, inout or contextual are read")
    func annotationSpellings() {
        let issues = analyze("""
        func root() throws -> InspectableView<ViewType.VStack> { fatalError() }

        func testSpellings(_ wrapped: Optional<InspectableView<ViewType.VStack>>,
                           _ mutable: inout InspectableView<ViewType.VStack>) throws {
            var first, second: InspectableView<ViewType.VStack>?
            _ = try first?.hStack(1)
            guard let checked: InspectableView<ViewType.VStack> = try? root() else { return }
            _ = try checked.hStack(2)
            _ = try wrapped?.hStack(3)
            _ = try mutable.hStack(4)
            let assertRow: (InspectableView<ViewType.HStack>) throws -> Void = { row in _ = try row.text(5) }
        }
        """)
        #expect(issues.map(\.lineNumber) == [8, 10, 11, 12, 13])
    }

    @Test("subscript and observer parameters and capture lists shadow an inspected name")
    func moreShadowing() {
        let issues = analyze("""
        final class ShadowTests: XCTestCase {
            var stack: InspectableView<ViewType.VStack>!

            subscript(stack: Wrapper) -> Int { _ = try? stack.hStack(1); return 0 }

            var observed: Wrapper = Wrapper() {
                willSet(stack) { _ = try? stack.hStack(2) }
            }

            func testCapture(other: Wrapper) {
                let check = { [stack = other] in _ = try? stack.hStack(3) }
            }
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test("a view made a View by an extension is test-owned by its own name")
    func qualifiedViewExtension() {
        let issues = analyze("""
        enum Fixtures { struct Card {} }
        extension Fixtures.Card: View { var body: some View { VStack { Text("a"); Text("b") } } }

        func testCard() throws {
            _ = try Fixtures.Card().inspect().vStack().text(1)
        }
        """)
        #expect(issues.isEmpty)
    }
}
