import Foundation

final class ProcessToken: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private(set) var isCancelled = false

    func attach(process: Process) {
        lock.lock()
        defer { lock.unlock() }
        self.process = process
        if isCancelled {
            process.terminate()
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        process = nil
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let currentProcess = process
        lock.unlock()
        currentProcess?.terminate()
    }
}
