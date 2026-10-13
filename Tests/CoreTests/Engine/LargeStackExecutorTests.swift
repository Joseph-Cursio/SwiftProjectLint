import Foundation
@testable import SwiftProjectLintEngine
import Testing

/// `LargeStackWorkers.withExecutor` runs analysis on deep stacks **without leaving the task tree**:
/// the run's `PackagePurity.current` binding is a task-local, and a pass that lost it would judge
/// with no table at all. So the stack and the task-local are checked together, in the body and in
/// the task-group children the per-file phase creates.
@Suite("The large-stack executor keeps work on the task tree")
struct LargeStackExecutorTests {

    @TaskLocal static var binding = "unbound"

    /// What a thread can recurse through: 512 KB on the cooperative pool.
    static var currentStackSize: Int {
        pthread_get_stacksize_np(pthread_self())
    }

    /// What one job saw: its stack, and the task-local.
    struct Observation: Sendable {
        let stackSize: Int
        let binding: String

        static var here: Self {
            Self(stackSize: LargeStackExecutorTests.currentStackSize, binding: LargeStackExecutorTests.binding)
        }
    }

    @Test("the body runs on a large stack before its first suspension")
    func bodyStartsOnALargeStack() async {
        // The pre-scan is synchronous and comes first in `analyzeDiscovered`: it must not have run
        // on the caller's thread before anything hopped.
        let size = await LargeStackWorkers.withExecutor { Self.currentStackSize }
        #expect(Self.currentStackSize < LargeStackWorkers.stackSize, "control: the test already has a large stack")
        #expect(size >= LargeStackWorkers.stackSize)
    }

    @Test("the body and its task-group children see the binding, on large stacks")
    func childTasksInheritTheBindingAndTheStack() async {
        let seen = await Self.$binding.withValue("bound") {
            await LargeStackWorkers.withExecutor {
                await withTaskGroup(of: Observation.self) { group in
                    for _ in 0..<16 { group.addTask { Observation.here } }
                    var seen = [Observation.here]
                    for await child in group { seen.append(child) }
                    return seen
                }
            }
        }
        #expect(seen.count == 17)
        #expect(seen.allSatisfy { $0.binding == "bound" }, "\(seen.map(\.binding))")
        #expect(seen.allSatisfy { $0.stackSize >= LargeStackWorkers.stackSize }, "\(seen.map(\.stackSize))")
    }
}
