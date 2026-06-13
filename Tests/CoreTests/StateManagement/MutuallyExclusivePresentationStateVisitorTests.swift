@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Tests for `MutuallyExclusivePresentationStateVisitor`.
///
/// The violating fixtures below are distilled from real TCA example code —
/// PointFree's `AlertsAndConfirmationDialogs` (`alert` + `confirmationDialog`)
/// and `VoiceMemos` (`alert` + `recordingMemo`) case studies model
/// mutually-exclusive modals as independent `@Presents` optionals. That code is
/// not buggy (modality prevents both at runtime), which is why the rule is an
/// opt-in `.info` refactor suggestion rather than an error.
@Suite
struct MutuallyExclusivePresentationStateVisitorTests {

    private func makeVisitor() -> MutuallyExclusivePresentationStateVisitor {
        let pattern = MutuallyExclusivePresentationState().pattern
        return MutuallyExclusivePresentationStateVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: MutuallyExclusivePresentationStateVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Flagged: two independent @Presents optionals

    @Test("Flags the AlertsAndConfirmationDialogs shape (alert + confirmationDialog)")
    func detectsTwoPresentsOptionals() throws {
        let source = """
        @ObservableState
        struct State: Equatable {
            @Presents var alert: AlertState<Action.Alert>?
            @Presents var confirmationDialog: ConfirmationDialogState<Action.ConfirmationDialog>?
            var count = 0
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .mutuallyExclusivePresentationState)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("State"))
        #expect(issue.message.contains("2"))
    }

    @Test("Flags the VoiceMemos shape (alert + recordingMemo)")
    func detectsVoiceMemosShape() {
        let source = """
        struct State {
            @Presents var alert: AlertState<Action.Alert>?
            @Presents var recordingMemo: RecordingMemo.State?
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test("Flags @PresentationState (older spelling)")
    func detectsPresentationStateSpelling() {
        let source = """
        struct State {
            @PresentationState var sheet: SheetFeature.State?
            @PresentationState var popover: PopoverFeature.State?
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test("Flags three presentation slots and reports the count")
    func detectsThreeSlots() throws {
        let source = """
        struct State {
            @Presents var alert: AlertState<Action.Alert>?
            @Presents var sheet: SheetFeature.State?
            @Presents var popover: PopoverFeature.State?
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("3"))
    }

    // MARK: - Not flagged: a single presentation optional

    @Test("No issue for a single @Presents optional")
    func noIssueForSingleOptional() {
        let source = """
        struct State {
            @Presents var alert: AlertState<Action.Alert>?
            var count = 0
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Not flagged: the idiomatic destination enum

    @Test("No issue for a single destination enum (illegal state unrepresentable)")
    func noIssueForDestinationEnum() {
        let source = """
        @ObservableState
        struct State {
            @Presents var destination: Destination.State?
            var count = 0
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Not flagged: @Presents on a non-Optional property

    @Test("No issue when @Presents properties are not Optional")
    func noIssueForNonOptionalPresents() {
        let source = """
        struct State {
            @Presents var alert: AlertState<Action.Alert>
            @Presents var dialog: ConfirmationDialogState<Action.Dialog>
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Not flagged: plain optionals without the annotation

    @Test("No issue for two plain optionals without @Presents")
    func noIssueForPlainOptionals() {
        let source = """
        struct State {
            var alert: AlertState<Action.Alert>?
            var confirmationDialog: ConfirmationDialogState<Action.Dialog>?
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Multiple offending structs

    @Test("Flags each offending struct independently")
    func detectsMultipleStructs() {
        let source = """
        struct AlertState1 {
            @Presents var alert: AlertState<A>?
            @Presents var dialog: ConfirmationDialogState<B>?
        }
        struct AlertState2 {
            @Presents var sheet: SheetFeature.State?
            @Presents var popover: PopoverFeature.State?
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 2)
    }
}
