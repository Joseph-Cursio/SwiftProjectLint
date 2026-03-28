//
//  RuleDocView.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 3/18/26.
//

import SwiftUI
import Core

// swiftprojectlint:disable:next large-view-body
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
        case heading2(String)
        case heading3(String)
        case codeBlock(String)
        case divider
        case paragraph(String)
        case spacer
    }

    private func parseBlocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var lineIndex = 0

        while lineIndex < lines.count {
            let line = lines[lineIndex]

            // Skip back-navigation link
            if line.hasPrefix("[←") { lineIndex += 1; continue }

            // H2
            if line.hasPrefix("## ") {
                blocks.append(.heading2(String(line.dropFirst(3))))
                lineIndex += 1; continue
            }

            // H3
            if line.hasPrefix("### ") {
                blocks.append(.heading3(String(line.dropFirst(4))))
                lineIndex += 1; continue
            }

            // Divider
            if line == "---" {
                blocks.append(.divider)
                lineIndex += 1; continue
            }

            // Fenced code block
            if line.hasPrefix("```") {
                lineIndex += 1
                var codeLines: [String] = []
                while lineIndex < lines.count && !lines[lineIndex].hasPrefix("```") {
                    codeLines.append(lines[lineIndex])
                    lineIndex += 1
                }
                lineIndex += 1 // consume closing ```
                blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
                continue
            }

            // Empty line
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blocks.append(.spacer)
                lineIndex += 1; continue
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
            }
        }

        return blocks
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
