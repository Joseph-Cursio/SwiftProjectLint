@testable import App
import Core
import Testing

/// `parseBlocks` must consume every line it is given.
///
/// It did not: a `#### ` heading matched no `singleLineBlock` arm, and the paragraph loop stops on any
/// `#` line without consuming it, so the outer loop saw the same line forever — on the main actor,
/// inside `body`. 29 of the 213 bundled rule docs carry a `####` heading, so opening any of them froze
/// the app. Found by swift-infer's `input-totality` law once its generator drew the function's own
/// `"#"` literal; the rendering tests above never opened one of the 29.
@Suite
@MainActor
struct RuleDocViewParseBlocksTests {

    private let view = RuleDocView(rule: .magicNumber)

    @Test func everyHeadingLevelIsConsumed() {
        let blocks = view.parseBlocks("# Title\n## Two\n### Three\n#### Four\n###### Six")
        #expect(blocks.count == 5)
        guard blocks.count == 5 else { return }
        if case let .heading2(text) = blocks[0] { #expect(text == "Title") } else { Issue.record("H1: \(blocks[0])") }
        if case let .heading3(text) = blocks[3] { #expect(text == "Four") } else { Issue.record("H4: \(blocks[3])") }
        if case let .heading3(text) = blocks[4] { #expect(text == "Six") } else { Issue.record("H6: \(blocks[4])") }
    }

    /// A bare `#` is a heading with no text; `#hashtag` is not a heading at all and stays text.
    @Test func bareAndNonHeadingHashesAreConsumed() {
        let blocks = view.parseBlocks("#\n#hashtag\nafter")
        #expect(blocks.count == 3)
        guard blocks.count == 3 else { return }
        guard case .spacer = blocks[0] else {
            Issue.record("bare # should be a spacer: \(blocks[0])")
            return
        }
        guard case let .paragraph(text) = blocks[1] else {
            Issue.record("#hashtag should stay text: \(blocks[1])")
            return
        }
        #expect(text == "#hashtag")
    }

    /// Every doc the app ships, parsed as the view parses it. A doc with a line the parser cannot
    /// consume would hang here, which is the failure this exists to surface before a user does.
    @Test func everyBundledRuleDocParses() {
        var parsed = 0
        for rule in RuleIdentifier.allCases {
            guard let markdown = RuleDocumentationLoader.loadDocumentation(for: rule) else { continue }
            #expect(view.parseBlocks(markdown).isEmpty == false, "no blocks for \(rule)")
            parsed += 1
        }
        #expect(parsed > 200, "expected the bundled docs to load; parsed \(parsed)")
    }
}
