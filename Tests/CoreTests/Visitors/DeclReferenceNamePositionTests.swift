import SwiftParser
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// The shared answer to "is this `DeclReferenceExprSyntax` a reference to the name, or only the
/// same spelling?" Every rule that asks whether a body uses a parameter, a local, a caught `error`
/// or a stored property now asks these predicates, so their edges are pinned here once.
@Suite
struct DeclReferenceNamePositionTests {

    /// Every `DeclReferenceExprSyntax` spelled `name` in `source`, in source order.
    private func references(named name: String, in source: String) -> [DeclReferenceExprSyntax] {
        let finder = ReferenceFinder(name: name)
        finder.walk(Parser.parse(source: source))
        return finder.found
    }

    private final class ReferenceFinder: SyntaxVisitor {
        let name: String
        var found: [DeclReferenceExprSyntax] = []

        init(name: String) {
            self.name = name
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            if node.baseName.text == name { found.append(node) }
            return .visitChildren
        }
    }

    // MARK: - Key-path components

    @Test func aKeyPathPropertyComponentIsANameOnly() {
        for source in ["rows.map(\\.total)", "rows.map(\\Row.total)", "rows.map(\\.total.description)"] {
            let found = references(named: "total", in: source)
            #expect(found.count == 1)
            #expect(found.first?.isKeyPathComponentName == true, "\(source)")
            #expect(found.first?.isLexicalReference == false, "\(source)")
        }
    }

    @Test func aSubscriptComponentsArgumentIsStillAReference() {
        // `\.[total]` reads the local `total`; only a component's *name* belongs to the root type.
        let found = references(named: "total", in: "rows.map(\\.[total])")
        #expect(found.count == 1)
        #expect(found.first?.isKeyPathComponentName == false)
        #expect(found.first?.isLexicalReference == true)
    }

    // MARK: - Member names

    @Test func aMemberOfAnotherValueIsANameOnly() {
        let found = references(named: "total", in: "order.total")
        #expect(found.first?.isMemberName == true)
        #expect(found.first?.isMemberNameOfOtherBase == true)
        #expect(found.first?.isLexicalReference == false)
    }

    @Test func aMemberOfSelfIsAMemberButNotOfAnotherBase() {
        // A stored property read through `self` is still this instance's; a local is not.
        for source in ["self.total", "self?.total", "self!.total", "(self).total", "((self))?.total"] {
            let found = references(named: "total", in: source)
            #expect(found.first?.isMemberName == true, "\(source)")
            #expect(found.first?.isMemberNameOfOtherBase == false, "\(source)")
            #expect(found.first?.isLexicalReference == false, "\(source)")
        }
    }

    @Test func aStaticOrImplicitMemberBelongsToAnotherBase() {
        for source in ["Self.total", "let x: Row = .total"] {
            let found = references(named: "total", in: source)
            #expect(found.first?.isMemberNameOfOtherBase == true, "\(source)")
            #expect(found.first?.isMemberName == true, "\(source)")
            #expect(found.first?.isLexicalReference == false, "\(source)")
        }
    }

    @Test func theBaseOfAMemberAccessIsStillAReference() {
        let found = references(named: "order", in: "order.total")
        #expect(found.first?.isMemberName == false)
        #expect(found.first?.isLexicalReference == true)
    }

    @Test func aBareNameIsAReference() {
        let found = references(named: "total", in: "print(total + 1)")
        #expect(found.first?.isKeyPathComponentName == false)
        #expect(found.first?.isMemberName == false)
        #expect(found.first?.isMemberNameOfOtherBase == false)
        #expect(found.first?.isLexicalReference == true)
    }
}
