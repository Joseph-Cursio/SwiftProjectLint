import Core
import SwiftUI

enum PatternCategoryColors {
    static func color(for category: PatternCategory) -> Color {
        switch category {
        case .stateManagement: .blue
        case .performance: .orange
        case .architecture: .purple
        case .codeQuality: .green
        case .security: .red
        case .accessibility: .teal
        case .memoryManagement: .pink
        case .networking: .cyan
        case .uiPatterns: .indigo
        case .animation: .mint
        case .modernization: .yellow
        case .idempotency: .brown
        case .other: .gray
        }
    }
}
