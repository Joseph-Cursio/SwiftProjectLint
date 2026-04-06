import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// Registers patterns related to API modernization.
/// This registrar handles patterns for outdated APIs that have modern Swift replacements,
/// including legacy C functions, GCD patterns, callback-based APIs, and deprecated SwiftUI patterns.

class Modernization: BasePatternRegistrar {
    override func registerPatterns() {
        registry.register(registrars: [
            DateNow(),
            DispatchMainAsync(),
            ThreadSleep(),
            LegacyRandom(),
            CFAbsoluteTime(),
            LegacyObserver(),
            CallbackDataTask(),
            TaskInOnAppear(),
            DispatchSemaphoreInAsync(),
            NavigationViewDeprecated(),
            OnChangeOldAPI(),
            LegacyObservableObject(),
            TaskSleepNanoseconds(),
            ForegroundColorDeprecated(),
            CornerRadiusDeprecated(),
            LegacyStringFormat(),
            ScrollViewReaderDeprecated(),
            LegacyReplacingOccurrences(),
            TabItemDeprecated(),
            LegacyFormatter(),
            LegacyImageRenderer(),
            ScrollViewShowsIndicators(),
            LegacyArrayInit(),
            LegacyClosureSyntax()
        ])
    }
}
