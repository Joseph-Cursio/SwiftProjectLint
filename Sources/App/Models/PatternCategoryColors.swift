import Core
import SwiftUI

// periphery:ignore
/// Maps a `PatternCategory` to the colour used to display it.
///
/// Unreferenced today, and deliberately kept: it is the colour half of the
/// `CategoryBadge<PatternCategory>` integration listed under "Adoption Path for
/// Unused Components" in `Docs/lintstudioui-shared-components.md`, and it backs
/// the `PatternCategory` → `LintCategory` row in that document's conformance
/// table. Periphery reports it as unused, which is true and not a reason to
/// delete it. If the adoption path is ever abandoned, remove this type *and*
/// both doc references together.
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
