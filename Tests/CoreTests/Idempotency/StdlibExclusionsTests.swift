import Testing
@testable import SwiftProjectLintVisitors

/// Fixtures for the stdlib-collection exclusion table. Covers every pair
/// in the exclusion set plus negative cases (non-matching receivers,
/// non-matching methods, unresolved receivers).
@Suite
struct StdlibExclusionsTests {

    // MARK: - Positive: every entry in the exclusion table matches

    @Test
    func arrayAppend_excluded() {
        #expect(StdlibExclusions.isExcluded(receiver: .stdlibCollection("Array"), method: "append"))
    }

    @Test
    func arrayInsert_excluded() {
        #expect(StdlibExclusions.isExcluded(receiver: .stdlibCollection("Array"), method: "insert"))
    }

    @Test
    func arrayRemove_excluded() {
        #expect(StdlibExclusions.isExcluded(receiver: .stdlibCollection("Array"), method: "remove"))
    }

    @Test
    func arrayRemoveAll_excluded() {
        #expect(StdlibExclusions.isExcluded(receiver: .stdlibCollection("Array"), method: "removeAll"))
    }

    @Test
    func arrayRemoveFirst_excluded() {
        #expect(StdlibExclusions.isExcluded(receiver: .stdlibCollection("Array"), method: "removeFirst"))
    }

    @Test
    func arrayRemoveLast_excluded() {
        #expect(StdlibExclusions.isExcluded(receiver: .stdlibCollection("Array"), method: "removeLast"))
    }

    @Test
    func stringAppend_excluded() {
        #expect(StdlibExclusions.isExcluded(receiver: .stdlibCollection("String"), method: "append"))
    }

    @Test
    func stringInsert_excluded() {
        #expect(StdlibExclusions.isExcluded(receiver: .stdlibCollection("String"), method: "insert"))
    }

    @Test
    func setInsert_excluded() {
        // Set.insert is idempotent by set semantics — the first-slice
        // bare-name whitelist incorrectly flagged this as non_idempotent
        // across the board. Receiver-type gating fixes it.
        #expect(StdlibExclusions.isExcluded(receiver: .stdlibCollection("Set"), method: "insert"))
    }

    @Test
    func setRemove_excluded() {
        #expect(StdlibExclusions.isExcluded(receiver: .stdlibCollection("Set"), method: "remove"))
    }

    @Test
    func setRemoveAll_excluded() {
        #expect(StdlibExclusions.isExcluded(receiver: .stdlibCollection("Set"), method: "removeAll"))
    }

    @Test
    func dictionaryRemoveValue_excluded() {
        #expect(StdlibExclusions.isExcluded(
            receiver: .stdlibCollection("Dictionary"), method: "removeValue"))
    }

    @Test
    func dictionaryUpdateValue_excluded() {
        #expect(StdlibExclusions.isExcluded(
            receiver: .stdlibCollection("Dictionary"), method: "updateValue"))
    }

    // MARK: - Negative: non-excluded methods on stdlib types

    @Test
    func arrayNotMethod_notExcluded() {
        // `Array.enqueue` isn't an Array method at all. Whether or not
        // the linter later flags `enqueue` on a user type, the (Array,
        // enqueue) pair must not suppress it.
        #expect(!StdlibExclusions.isExcluded(
            receiver: .stdlibCollection("Array"), method: "enqueue"))
    }

    @Test
    func dictionaryInsert_notExcluded() {
        // Dictionary has no `insert` method. Don't suppress.
        #expect(!StdlibExclusions.isExcluded(
            receiver: .stdlibCollection("Dictionary"), method: "insert"))
    }

    // MARK: - Negative: named (user-defined) receivers are never excluded

    @Test
    func namedReceiverAppend_notExcluded() {
        // `queue.append(...)` where `queue: UserDefinedQueue`. The bare
        // name `append` should still classify this as non_idempotent.
        #expect(!StdlibExclusions.isExcluded(
            receiver: .named("UserDefinedQueue"), method: "append"))
    }

    @Test
    func namedReceiverInsert_notExcluded() {
        #expect(!StdlibExclusions.isExcluded(
            receiver: .named("Database"), method: "insert"))
    }

    @Test
    func namedReceiverWithStdlibName_notExcluded() {
        // Paranoid case: even if a user declares their own type named
        // "Array", the resolver downgrades to `.named("Array")` (see
        // `localTypeShadowsStdlibName_downgradesToNamed` in the resolver
        // tests). The exclusion table only matches `.stdlibCollection`.
        #expect(!StdlibExclusions.isExcluded(
            receiver: .named("Array"), method: "append"))
    }

    // MARK: - Negative: unresolved receivers are never excluded

    @Test
    func unresolvedReceiver_notExcluded() {
        #expect(!StdlibExclusions.isExcluded(receiver: .unresolved, method: "append"))
    }
}
