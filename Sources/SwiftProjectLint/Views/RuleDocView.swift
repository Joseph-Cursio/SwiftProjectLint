//
//  RuleDocView.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 3/18/26.
//

import SwiftUI
import SwiftProjectLintCore

/// Renders the markdown documentation for a single lint rule.
struct RuleDocView: View {
    let rule: RuleIdentifier

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

    private enum Block {
        case h2(String)
        case h3(String)
        case codeBlock(String)
        case divider
        case paragraph(String)
        case spacer
    }

    private func parseBlocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Skip back-navigation link
            if line.hasPrefix("[←") { i += 1; continue }

            // H2
            if line.hasPrefix("## ") {
                blocks.append(.h2(String(line.dropFirst(3))))
                i += 1; continue
            }

            // H3
            if line.hasPrefix("### ") {
                blocks.append(.h3(String(line.dropFirst(4))))
                i += 1; continue
            }

            // Divider
            if line == "---" {
                blocks.append(.divider)
                i += 1; continue
            }

            // Fenced code block
            if line.hasPrefix("```") {
                i += 1
                var codeLines: [String] = []
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                i += 1 // consume closing ```
                blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
                continue
            }

            // Empty line
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blocks.append(.spacer)
                i += 1; continue
            }

            // Paragraph — collect consecutive non-special lines
            var paragraphLines: [String] = []
            while i < lines.count {
                let l = lines[i]
                if l.isEmpty
                    || l.hasPrefix("#")
                    || l.hasPrefix("```")
                    || l == "---"
                    || l.hasPrefix("[←") { break }
                paragraphLines.append(l)
                i += 1
            }
            if !paragraphLines.isEmpty {
                blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
            }
        }

        return blocks
    }

    // MARK: - Block rendering

    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .h2(let text):
            Text(text)
                .font(.title2)
                .bold()
                .padding(.top, 20)
                .padding(.bottom, 6)

        case .h3(let text):
            Text(text)
                .font(.headline)
                .padding(.top, 14)
                .padding(.bottom, 4)

        case .codeBlock(let code):
            Text(code)
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
