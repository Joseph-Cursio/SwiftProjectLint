//
//  RuleDocView.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 3/18/26.
//

import Core
import SwiftUI

// swiftprojectlint:disable:next large-view-body
/// Renders the markdown documentation for a single lint rule.
struct RuleDocView: View {
    let rule: RuleIdentifier

    @Environment(\.colorScheme) private var colorScheme

    private var markdown: String {
        RuleDocumentationLoader.loadDocumentation(for: rule)
            ?? "_Documentation not available for this rule._"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(parseBlocks(markdown).enumerated()), id: \.offset) { _, block in
                    renderBlock(block)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Markdown blocks

    enum Block {
        case heading2(String)
        case heading3(String)
        case codeBlock(String)
        case divider
        case paragraph(String)
        case spacer
    }

    func parseBlocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var lineIndex = 0

        while lineIndex < lines.count {
            let line = lines[lineIndex]

            // Skip back-navigation link
            if line.hasPrefix("[←") { lineIndex += 1; continue }

            if let block = singleLineBlock(from: line) {
                blocks.append(block)
                lineIndex += 1
                continue
            }

            // Fenced code block
            if line.hasPrefix("```") {
                let (codeBlock, nextIndex) = parseFencedCode(lines: lines, startIndex: lineIndex)
                blocks.append(codeBlock)
                lineIndex = nextIndex
                continue
            }

            // Paragraph — collect consecutive non-special lines
            var paragraphLines: [String] = []
            while lineIndex < lines.count {
                let currentLine = lines[lineIndex]
                if currentLine.isEmpty
                    || currentLine.hasPrefix("#")
                    || currentLine.hasPrefix("```")
                    || currentLine == "---"
                    || currentLine.hasPrefix("[←") { break }
                paragraphLines.append(currentLine)
                lineIndex += 1
            }
            if !paragraphLines.isEmpty {
                blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
            } else {
                // Every iteration must consume a line. The paragraph loop stops on any `#`, blank,
                // fence, `---` or `[←` line without consuming it, so a line that `singleLineBlock`
                // does not recognise AND that stops the paragraph loop was seen forever — which is
                // what a `#### ` heading did, freezing the app on 29 of the bundled rule docs.
                // Rendering it as a one-line paragraph makes termination a property of this loop
                // rather than of the two stop lists agreeing.
                blocks.append(.paragraph(line))
                lineIndex += 1
            }
        }

        return blocks
    }

    /// Single-line block recognisers: headings, dividers, and the empty
    /// spacer. Folded out of `parseBlocks` so the main loop only handles
    /// multi-line shapes (fenced code, paragraphs) and the back-nav skip.
    func singleLineBlock(from line: String) -> Block? {
        if line.hasPrefix("## ") { return .heading2(String(line.dropFirst(3))) }
        if line.hasPrefix("### ") { return .heading3(String(line.dropFirst(4))) }
        // Every other ATX heading level: `# Title` (H1) and `####`–`######`. Only a real heading —
        // 1–6 `#` then a space or the end of the line — so `#hashtag` stays paragraph text.
        if let heading = Self.otherHeading(line) { return heading }
        if line == "---" { return .divider }
        if line.trimmingCharacters(in: .whitespaces).isEmpty { return .spacer }
        return nil
    }

    /// An H1 or H4–H6 heading as the nearest block this view renders, or `nil` for anything else.
    /// A heading with no text — a bare `#` — is a spacer.
    static func otherHeading(_ line: String) -> Block? {
        let level = line.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        guard rest.isEmpty || rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return .spacer }
        return level == 1 ? .heading2(text) : .heading3(text)
    }

    /// Parses a fenced code block starting at the opening ``` line and
    /// returns the constructed block plus the index of the line *after*
    /// the closing fence. Extracted from `parseBlocks` to keep its
    /// cyclomatic complexity within the SwiftLint budget.
    private func parseFencedCode(lines: [String], startIndex: Int) -> (Block, Int) {
        var lineIndex = startIndex + 1
        var codeLines: [String] = []
        while lineIndex < lines.count, !lines[lineIndex].hasPrefix("```") {
            codeLines.append(lines[lineIndex])
            lineIndex += 1
        }
        return (.codeBlock(codeLines.joined(separator: "\n")), lineIndex + 1)
    }

    // MARK: - Block rendering

    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .heading2(let text):
            Text(text)
                .font(.title2)
                .bold()
                .padding(.top, 20)
                .padding(.bottom, 6)

        case .heading3(let text):
            Text(text)
                .font(.headline)
                .padding(.top, 14)
                .padding(.bottom, 4)

        case .codeBlock(let code):
            Text(highlightedCode(code, colorScheme: colorScheme))
                .font(.system(.callout, design: .monospaced))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.1))
                .clipShape(.rect(cornerRadius: 6))
                .padding(.vertical, 4)

        case .divider:
            Divider()
                .padding(.vertical, 10)

        case .paragraph(let text):
            Group {
                if let attributed = try? AttributedString(markdown: text) {
                    Text(attributed)
                } else {
                    Text(text)
                }
            }
            .padding(.bottom, 6)
            .fixedSize(horizontal: false, vertical: true)

        case .spacer:
            Color.clear.frame(height: 6)
        }
    }
}

#Preview {
    RuleDocView(rule: .relatedDuplicateStateVariable)
        .frame(width: 600, height: 700)
}
