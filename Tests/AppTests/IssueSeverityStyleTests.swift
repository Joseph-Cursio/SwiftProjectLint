@testable import App
@testable import Core
import SwiftUI
import Testing

/// Laws over the severity-to-appearance mapping, which could not be stated while it lived as three
/// `private var`s inside `LintIssueRow`.
///
/// `LintIssueRowTests` already covers this mapping — `errorSeverityIcon`, `warningSeverityIcon`,
/// `infoSeverityIcon` — by building a whole row and inspecting it, one example per severity. Those
/// stay; they check that the row actually *uses* the style. What they cannot express is anything
/// about the severities as a set, because each of them looks at one case in isolation.
///
/// Both laws below are of that kind, and both are the sort a fourth severity would break silently.
@Suite("Severity appearance")
struct IssueSeverityStyleTests {

    // MARK: - Totality

    @Test("every severity has a style")
    func everySeverityHasAStyle() {
        // Vacuous today, and worth being honest that it is: the switch is exhaustive with no
        // `default:`, so it cannot fail to produce a style, and adding a case is a compile error
        // until every arm is written. That was checked by adding a fourth case — the build stopped
        // in `LintConfigurationWriter` before any test ran. It stays as the statement of the
        // property, not as the thing catching it.
        for severity in IssueSeverity.allCases {
            let style = IssueSeverityStyle(severity)
            #expect(!style.iconName.isEmpty, "\(severity) has no icon")
            #expect(!style.accessibilityLabel.isEmpty, "\(severity) has no label")
        }
    }

    @Test("the accessibility label names the severity")
    func labelNamesTheSeverity() {
        // Ties the label to the enum rather than to a string literal typed three times. A new case
        // whose label was copy-pasted from its neighbour fails here.
        for severity in IssueSeverity.allCases {
            #expect(IssueSeverityStyle(severity).accessibilityLabel == severity.rawValue.capitalized)
        }
    }

    // MARK: - Distinctness, which is the law nobody had written

    @Test("no two severities share an icon")
    func iconsAreDistinct() {
        // What the compiler cannot enforce. It makes you write an arm for a new severity; nothing
        // makes that arm *differ* from its neighbours, and a copy-pasted arm is how a new case ends
        // up drawn exactly like an old one. A severity row is read at a glance, so two identical
        // ones are unreadable.
        //
        // For today's three cases this is not stronger than the example tests in
        // `LintIssueRowTests` — duplicating warning's icon fails there too, because someone wrote
        // an example naming `exclamationmark.triangle.fill`. It becomes stronger for the case
        // nobody has written an example for yet, which is every case added after this one.
        let icons = IssueSeverity.allCases.map { IssueSeverityStyle($0).iconName }
        #expect(Set(icons).count == icons.count, "duplicate icon among \(icons)")
    }

    @Test("no two severities share a colour")
    func coloursAreDistinct() {
        let colours = IssueSeverity.allCases.map { IssueSeverityStyle($0).color }
        #expect(Set(colours).count == colours.count, "duplicate colour among \(colours)")
    }

    @Test("no two severities share an accessibility label")
    func labelsAreDistinct() {
        // The one that matters most to a VoiceOver user: two severities read aloud identically is
        // the same defect as two drawn identically, and less likely to be noticed by eye.
        let labels = IssueSeverity.allCases.map { IssueSeverityStyle($0).accessibilityLabel }
        #expect(Set(labels).count == labels.count, "duplicate label among \(labels)")
    }
}
