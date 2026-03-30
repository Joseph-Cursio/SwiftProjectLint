import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct AccessibilityTreeTraverserTests {

    // MARK: - Helper

    /// Parses source code and returns the first FunctionCallExprSyntax matching the given name.
    private func findFirstCall(named name: String, in source: String) -> FunctionCallExprSyntax? {
        let tree = Parser.parse(source: source)
        class CallFinder: SyntaxVisitor {
            let target: String
            var found: FunctionCallExprSyntax?
            init(target: String) {
                self.target = target
                super.init(viewMode: .sourceAccurate)
            }
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                if found == nil,
                   let ref = node.calledExpression.as(DeclReferenceExprSyntax.self),
                   ref.baseName.text == target {
                    found = node
                }
                return .visitChildren
            }
        }
        let finder = CallFinder(target: name)
        finder.walk(tree)
        return finder.found
    }

    // MARK: - hasAccessibilityModifier

    @Test func hasAccessibilityModifierReturnsTrueWhenPresent() throws {
        let source = """
        Button("Tap") { action() }
            .accessibilityLabel("Tap button")
        """
        let button = try #require(findFirstCall(named: "Button", in: source))
        #expect(AccessibilityTreeTraverser.hasAccessibilityModifier(in: button, modifierName: "accessibilityLabel"))
    }

    @Test func hasAccessibilityModifierReturnsFalseWhenAbsent() throws {
        let source = """
        Button("Tap") { action() }
            .padding()
        """
        let button = try #require(findFirstCall(named: "Button", in: source))
        #expect(
            AccessibilityTreeTraverser.hasAccessibilityModifier(
                in: button, modifierName: "accessibilityLabel"
            ) == false
        )

    }

    @Test func hasAccessibilityModifierReturnsFalseForUnknownModifier() throws {
        let source = """
        Button("Tap") { action() }
            .foregroundColor(.red)
        """
        let button = try #require(findFirstCall(named: "Button", in: source))
        // "foregroundColor" is not in the accessibility modifiers set
        #expect(
            AccessibilityTreeTraverser.hasAccessibilityModifier(
                in: button, modifierName: "foregroundColor"
            ) == false
        )

    }

    @Test func hasAccessibilityModifierFindsHintInChain() throws {
        let source = """
        Button("Tap") { action() }
            .accessibilityLabel("label")
            .accessibilityHint("hint")
            .padding()
        """
        let button = try #require(findFirstCall(named: "Button", in: source))
        #expect(AccessibilityTreeTraverser.hasAccessibilityModifier(in: button, modifierName: "accessibilityHint"))
    }

    @Test func hasAccessibilityModifierReturnsFalseForStandaloneNode() throws {
        // Button with no modifiers at all
        let source = """
        Button("Tap") { action() }
        """
        let button = try #require(findFirstCall(named: "Button", in: source))
        #expect(
            AccessibilityTreeTraverser.hasAccessibilityModifier(
                in: button, modifierName: "accessibilityLabel"
            ) == false
        )

    }

    // MARK: - buttonHasStringTitle

    @Test func buttonHasStringTitleReturnsTrueForStringLiteral() throws {
        let source = """
        Button("Send") { action() }
        """
        let button = try #require(findFirstCall(named: "Button", in: source))
        #expect(AccessibilityTreeTraverser.buttonHasStringTitle(button))
    }

    @Test func buttonHasStringTitleReturnsTrueForSystemImageInit() throws {
        let source = """
        Button("Send", systemImage: "paperplane") { action() }
        """
        let button = try #require(findFirstCall(named: "Button", in: source))
        #expect(AccessibilityTreeTraverser.buttonHasStringTitle(button))
    }

    @Test func buttonHasStringTitleReturnsFalseForLabeledArgs() throws {
        let source = """
        Button(action: { doThing() }) { Image("icon") }
        """
        let button = try #require(findFirstCall(named: "Button", in: source))
        #expect(AccessibilityTreeTraverser.buttonHasStringTitle(button) == false)

    }

    @Test func buttonHasStringTitleReturnsFalseForTrailingClosureOnly() throws {
        let source = """
        Button { doThing() } label: { Text("hello") }
        """
        let button = try #require(findFirstCall(named: "Button", in: source))
        #expect(AccessibilityTreeTraverser.buttonHasStringTitle(button) == false)

    }

    // MARK: - findImages

    @Test func findImagesReturnsEmptyForNoImages() {
        let source = """
        VStack { Text("hello") }
        """
        let tree = Parser.parse(source: source)
        let images = AccessibilityTreeTraverser.findImages(in: Syntax(tree))
        #expect(images.isEmpty)
    }

    @Test func findImagesFindsDirectImage() {
        let source = """
        Image("icon")
        """
        let tree = Parser.parse(source: source)
        let images = AccessibilityTreeTraverser.findImages(in: Syntax(tree))
        #expect(images.count == 1)
    }

    @Test func findImagesFindsMultipleNestedImages() {
        let source = """
        VStack {
            Image("one")
            HStack {
                Image("two")
                Image("three")
            }
        }
        """
        let tree = Parser.parse(source: source)
        let images = AccessibilityTreeTraverser.findImages(in: Syntax(tree))
        #expect(images.count == 3)
    }

    // MARK: - containsImage

    @Test func containsImageReturnsTrueForNestedImage() {
        let source = """
        HStack { Image(systemName: "star") }
        """
        let tree = Parser.parse(source: source)
        #expect(AccessibilityTreeTraverser.containsImage(in: Syntax(tree)))
    }

    @Test func containsImageReturnsFalseWhenNoImage() {
        let source = """
        HStack { Text("hello") }
        """
        let tree = Parser.parse(source: source)
        #expect(AccessibilityTreeTraverser.containsImage(in: Syntax(tree)) == false)

    }

    // MARK: - containsText

    @Test func containsTextReturnsTrueForNestedText() {
        let source = """
        VStack { Text("hello") }
        """
        let tree = Parser.parse(source: source)
        #expect(AccessibilityTreeTraverser.containsText(in: Syntax(tree)))
    }

    @Test func containsTextReturnsFalseWhenNoText() {
        let source = """
        VStack { Image("icon") }
        """
        let tree = Parser.parse(source: source)
        #expect(AccessibilityTreeTraverser.containsText(in: Syntax(tree)) == false)

    }

    @Test func containsTextFindsDeepNestedText() {
        let source = """
        ScrollView {
            LazyVStack {
                ForEach(items) { item in
                    Text(item.name)
                }
            }
        }
        """
        let tree = Parser.parse(source: source)
        #expect(AccessibilityTreeTraverser.containsText(in: Syntax(tree)))
    }
}
