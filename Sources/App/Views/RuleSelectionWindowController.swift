import AppKit
import SwiftUI
import Core

/// Manages a standalone NSWindow for the rule selection dialog.
///
/// Using a real NSWindow instead of a SwiftUI sheet gives us:
/// - Resizable and movable window
/// - Proper keyboard focus (arrow keys work in the List)
/// - Standard macOS window chrome
/// Configuration for presenting the rule selection window.
struct RuleSelectionConfig {
    let allPatternsByCategory: [PatternCategoryInfo]
    let enabledRuleNames: Binding<Set<RuleIdentifier>>
    let ruleExclusions: Binding<[RuleIdentifier: RuleExclusions]>
    let configIsDirty: Bool
    let onSave: () -> Void
    let onSaveConfig: () -> Void
    let onDismiss: () -> Void
}

@MainActor
final class RuleSelectionWindowController {
    static let shared = RuleSelectionWindowController()

    private var window: NSWindow?
    private var windowCloseHandler: WindowCloseDelegate?

    func show(config: RuleSelectionConfig) {
        // Close existing window if open
        window?.close()

        let dialog = RuleSelectionDialog(
            allPatternsByCategory: config.allPatternsByCategory,
            enabledRuleNames: config.enabledRuleNames,
            ruleExclusions: config.ruleExclusions,
            configIsDirty: config.configIsDirty,
            onSave: config.onSave,
            onSaveConfig: config.onSaveConfig,
            onDismiss: config.onDismiss
        )

        let hostingView = NSHostingView(rootView: dialog)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Select Rules"
        newWindow.contentView = hostingView
        newWindow.minSize = NSSize(width: 900, height: 500)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        let delegate = WindowCloseDelegate(onClose: config.onDismiss)
        self.windowCloseHandler = delegate
        newWindow.delegate = delegate

        newWindow.makeKeyAndOrderFront(nil)
        self.window = newWindow
    }

    func close() {
        window?.close()
        window = nil
        windowCloseHandler = nil
    }
}

/// Calls the dismiss handler when the user closes the window via the red button.
private final class WindowCloseDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
