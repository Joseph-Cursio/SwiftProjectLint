import Core
import SwiftUI

enum PatternCategoryColors {
    // Table lookup keeps `color(for:)` under SwiftLint's cyclomatic-complexity
    // budget. `.other` is both an explicit entry and the fallback colour, so
    // any future category added without a palette entry degrades to the same
    // neutral colour rather than crashing.
    private static let palette: [PatternCategory: Color] = [
        .stateManagement: .blue,
        .performance: .orange,
        .architecture: .purple,
        .codeQuality: .green,
        .security: .red,
        .accessibility: .teal,
        .memoryManagement: .pink,
        .networking: .cyan,
        .uiPatterns: .indigo,
        .animation: .mint,
        .modernization: .yellow,
        .idempotency: .brown,
        .other: .gray
    ]

    static func color(for category: PatternCategory) -> Color {
        palette[category] ?? .gray
    }
}
