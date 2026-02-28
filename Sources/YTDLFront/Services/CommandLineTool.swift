import Foundation

struct CommandResult {
    let exitCode: Int32
    let output: String
}

enum CommandLineToolError: LocalizedError {
    case couldNotLaunch(String)

    var errorDescription: String? {
        switch self {
        case .couldNotLaunch(let message):
            return message
        }
    }
}

enum CommandLineTool {
    static func run(executableURL: URL, arguments: [String]) async throws -> CommandResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        return try await withCheckedThrowingContinuation { continuation in
            let collector = CommandOutputCollector()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    return
                }
                collector.append(chunk)
            }

            process.terminationHandler = { terminatedProcess in
                pipe.fileHandleForReading.readabilityHandler = nil
                let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = collector.finalize(with: remaining)

                continuation.resume(returning: CommandResult(exitCode: terminatedProcess.terminationStatus, output: output))
            }

            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: CommandLineToolError.couldNotLaunch("Execution impossible: \(error.localizedDescription)"))
            }
        }
    }
}

private final class CommandOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var outputData = Data()

    func append(_ chunk: Data) {
        lock.lock()
        outputData.append(chunk)
        lock.unlock()
    }

    func finalize(with remaining: Data) -> String {
        lock.lock()
        outputData.append(remaining)
        let output = String(decoding: outputData, as: UTF8.self)
        lock.unlock()
        return output
    }
}
