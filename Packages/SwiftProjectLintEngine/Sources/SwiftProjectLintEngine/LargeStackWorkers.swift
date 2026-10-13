import Foundation

/// Work that recurses as deep as the source it reads, run on threads whose stack is sized for it,
/// and awaited without blocking the caller's thread.
///
/// ## Why threads
///
/// swift-syntax's parser recurses once per nesting level — an `else if` arm is one — and a
/// `SyntaxVisitor` walk recurses once per node level, so a 10,000-link member chain is 10,000
/// nested frames. A Swift-concurrency thread has about **512 KB** of stack, and overflowing it is
/// not an error anyone can catch: it is `SIGBUS` on the guard page, and the whole process goes.
/// Measured on the construction-facts wiring: a 1,000-arm `else if` chain in a nested dependency
/// package crashed the run in `Parser.parseIfExpression`, and a 10,000-link member chain in
/// `ConstructionFacts.build`. Neither file is reported on — before the universe, no run read it.
/// SwiftInferProperties met the same trap on GCD's workers and answered it the same way.
///
/// So the shared parse, the facts build and the universe's manifest reads run here, on `Thread`s
/// with ``stackSize`` (``map`` and ``run``). The manifests came last: a nested dependency's
/// `Package.swift` with a 1,000-arm `else if` crashed the bound's manifest reader just as a source
/// file crashed the parse.
///
/// The analysis after them — the pre-scan, per-file and cross-file phases — walks every reported
/// file just as deep, and reached the same trap from the other side: a 200-link member chain in a
/// reported file crashed a debug run in the pre-scan (`FunctionTypeAliasCollector`), whichever rules
/// were enabled; with that walk out of the way a 500-link one crashed in swift-syntax's own
/// `RawSyntax.withEachSyntaxText`, and a release build crashed from about 900 links. So it runs on
/// the same stacks through ``withExecutor``, which, unlike the other two, stays on the task tree.
///
/// ## Why this is safe for the run's task-local
///
/// A thread does not inherit `PackagePurity.current`, which is why `PurityOracleEntryTests` forbids
/// leaving the task tree. Every caller of ``map`` and ``run`` runs **before** `ProjectLinter.pass`
/// binds it, and none creates an oracle that reads it: the parse and the manifest reads create none,
/// and `ConstructionFacts.build` is SEI's own pass. ``withExecutor`` runs inside the binding, and
/// may: a task-executor preference moves the task's jobs to other threads, not out of the task, so
/// the binding is inherited. The test names this file as its one exception, checks that only those
/// callers use ``map`` and ``run``, and that only `pass` uses ``withExecutor``.
enum LargeStackWorkers {

    /// Eight times the main thread's 8 MB. In a debug build the two regression fixtures
    /// (`PackagePurityRobustnessTests`) crash at 4 MB and pass at 16 MB, so this leaves four times
    /// that for deeper sources; the reported 10,000-link chain the whole analysis walks
    /// (`DeepReportedFileTests`) crashes at 16 MB and passes at 32 MB, which leaves twice that.
    /// Reserved, not committed: a thread touches only the pages it uses.
    static let stackSize = 64 << 20

    /// `body(index)` for every index in `0..<count`, across up to one thread per active core, each
    /// with ``stackSize``; the results in index order. Once the calling task is cancelled no
    /// further index starts, and an index left unrun has `nil`.
    static func map<Result: Sendable>(
        _ count: Int,
        _ body: @escaping @Sendable (Int) -> Result
    ) async -> [Result?] {
        guard count > 0 else { return [] }
        let batch = Batch<Result>(count: count, workers: min(ProcessInfo.processInfo.activeProcessorCount, count))
        await withTaskCancellationHandler {
            await start(batch, body)
        } onCancel: {
            batch.cancel()
        }
        return batch.results
    }

    /// `body`'s result, computed on one thread with ``stackSize``. It always runs: there is no
    /// smaller stack to fall back to, and the caller needs the value.
    static func run<Result: Sendable>(_ body: @escaping @Sendable () -> Result) async -> Result {
        let batch = Batch<Result>(count: 1, workers: 1)
        await start(batch) { _ in body() }
        guard case let result?? = batch.results.first else {
            preconditionFailure("a large-stack worker returned without running")
        }
        return result
    }

    /// `body`, with every job of the calling task, and of each child task it creates, run on threads
    /// with ``stackSize``.
    ///
    /// Unlike ``map`` and ``run`` this does not leave the task tree. It is a task-executor
    /// preference (SE-0417): it changes which threads run the task's jobs, not which task they
    /// belong to, so task-locals (`PackagePurity.current` among them), cancellation and task-group
    /// children are inherited exactly as on the cooperative pool. The threads, one per active core,
    /// are this call's own and end with it.
    static func withExecutor<Result>(_ body: () async -> Result) async -> Result {
        let executor = Executor(threads: ProcessInfo.processInfo.activeProcessorCount)
        defer { executor.finish() }
        return await withTaskExecutorPreference(executor, operation: body)
    }

    /// Starts `batch.workers` threads draining `batch`, and returns when the last has finished —
    /// suspended, not blocking: the caller's thread goes back to the pool meanwhile.
    private static func start<Result: Sendable>(
        _ batch: Batch<Result>,
        _ body: @escaping @Sendable (Int) -> Result
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            batch.whenDone(continuation)
            for _ in 0..<batch.workers {
                let thread = Thread {
                    while let index = batch.next() { batch.store(body(index), at: index) }
                    batch.workerFinished()
                }
                thread.stackSize = stackSize
                thread.start()
            }
        }
    }

    /// The shared state of one `map`: the next index, the results, and who resumes the caller.
    private final class Batch<Result: Sendable>: @unchecked Sendable {
        let workers: Int
        private let count: Int
        private let lock = NSLock()
        private var nextIndex = 0
        private var cancelled = false
        private var running: Int
        private var slots: [Result?]
        private var continuation: CheckedContinuation<Void, Never>?

        init(count: Int, workers: Int) {
            self.count = count
            self.workers = max(workers, 1)
            running = self.workers
            slots = Array(repeating: nil, count: count)
        }

        var results: [Result?] {
            lock.withLock { slots }
        }

        func whenDone(_ continuation: CheckedContinuation<Void, Never>) {
            lock.withLock { self.continuation = continuation }
        }

        /// The next unclaimed index, or `nil` once all are claimed or the caller was cancelled.
        func next() -> Int? {
            lock.withLock {
                guard !cancelled, nextIndex < count else { return nil }
                nextIndex += 1
                return nextIndex - 1
            }
        }

        func store(_ result: Result, at index: Int) {
            lock.withLock { slots[index] = result }
        }

        func cancel() {
            lock.withLock { cancelled = true }
        }

        /// The last worker out resumes the caller, exactly once.
        func workerFinished() {
            let resume: CheckedContinuation<Void, Never>? = lock.withLock {
                running -= 1
                guard running == 0 else { return nil }
                defer { continuation = nil }
                return continuation
            }
            resume?.resume()
        }
    }

    /// The task executor behind ``withExecutor``: a queue of jobs drained by threads with
    /// ``stackSize``, which end once it is finished and the queue is empty.
    private final class Executor: TaskExecutor, @unchecked Sendable {
        private let condition = NSCondition()
        private var jobs: [UnownedJob] = []
        private var finished = false

        init(threads: Int) {
            for _ in 0..<max(threads, 1) { startThread() }
        }

        func enqueue(_ job: consuming ExecutorJob) {
            let job = UnownedJob(job)
            let orphaned: Bool = condition.withLock {
                jobs.append(job)
                condition.signal()
                return finished
            }
            // Nothing is enqueued once the preference is gone, but were a job to arrive then, its
            // own thread runs it rather than nobody.
            if orphaned { startThread() }
        }

        /// Lets every thread end once the queue is empty, rather than wait for more.
        func finish() {
            condition.withLock {
                finished = true
                condition.broadcast()
            }
        }

        private func startThread() {
            let thread = Thread { [self] in
                while let job = next() { job.runSynchronously(on: asUnownedTaskExecutor()) }
            }
            thread.stackSize = LargeStackWorkers.stackSize
            thread.start()
        }

        /// The oldest job, waiting for one while the executor is in use; `nil` once it is finished
        /// and none is left.
        private func next() -> UnownedJob? {
            condition.withLock {
                while jobs.isEmpty {
                    if finished { return nil }
                    condition.wait()
                }
                return jobs.removeFirst()
            }
        }
    }
}
