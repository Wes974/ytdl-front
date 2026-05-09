import Foundation

enum DownloadRunnerError: LocalizedError {
    case ytDlpFailed(String)
    case noOutputFile

    var errorDescription: String? {
        switch self {
        case .ytDlpFailed(let message):
            return message
        case .noOutputFile:
            return "Le telechargement est termine mais le fichier de sortie est introuvable."
        }
    }
}

enum DownloadEvent {
    case progress(Double)
    case status(String)
    case log(String)
}

struct DownloadResult {
    let outputURL: URL
}

final class DownloadRunner: @unchecked Sendable {
    private let binaryManager: BinaryManager

    init(binaryManager: BinaryManager) {
        self.binaryManager = binaryManager
    }

    func downloadVideo(
        from remoteURL: URL,
        outputDirectory: URL,
        token: ProcessToken,
        onEvent: @escaping @Sendable (DownloadEvent) -> Void
    ) async throws -> DownloadResult {
        let outputTemplate = "%(title).120B [%(id)s].%(ext)s"

        let directMP4Args: [String] = [
            "--no-playlist",
            "--newline",
            "--progress",
            "--ffmpeg-location", binaryManager.binDirectory.path,
            "--print", "after_move:__YTDL_FILE__:%(filepath)s",
            "--paths", outputDirectory.path,
            "-o", outputTemplate,
            "-f", "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/b",
            "--merge-output-format", "mp4",
            remoteURL.absoluteString
        ]

        let fallbackArgs: [String] = [
            "--no-playlist",
            "--newline",
            "--progress",
            "--ffmpeg-location", binaryManager.binDirectory.path,
            "--print", "after_move:__YTDL_FILE__:%(filepath)s",
            "--paths", outputDirectory.path,
            "-o", outputTemplate,
            "-f", "bv*+ba/b",
            "--merge-output-format", "mp4",
            "--recode-video", "mp4",
            remoteURL.absoluteString
        ]

        var firstPassPaths: [String] = []
        do {
            firstPassPaths = try await runYTDLP(arguments: directMP4Args, token: token, onEvent: onEvent)
            if let merged = pickMergedMP4(from: firstPassPaths) {
                return DownloadResult(outputURL: merged)
            }
            onEvent(.log("[YTDLFront] Sortie non-mergee detectee, fallback recodage MP4."))
        } catch {
            if token.isCancelled {
                throw CancellationError()
            }
            onEvent(.log("[YTDLFront] Premiere passe yt-dlp echouee, fallback recodage MP4."))
        }

        // Remove any residual files from the first pass so the fallback can re-create them cleanly.
        for path in firstPassPaths {
            try? FileManager.default.removeItem(atPath: path)
        }

        let fallbackPaths = try await runYTDLP(arguments: fallbackArgs, token: token, onEvent: onEvent)
        guard let merged = pickMergedMP4(from: fallbackPaths) else {
            throw DownloadRunnerError.noOutputFile
        }
        return DownloadResult(outputURL: merged)
    }

    private func pickMergedMP4(from paths: [String]) -> URL? {
        // After a successful merge, yt-dlp emits exactly one `after_move` line for the final .mp4.
        // Multiple paths or a non-mp4 path means the merge was skipped (e.g. ffmpeg unusable) and
        // the result is a silent .mp4 + side .m4a — caller should retry with --recode-video.
        guard paths.count == 1, paths[0].lowercased().hasSuffix(".mp4") else {
            return nil
        }
        return URL(fileURLWithPath: paths[0])
    }

    private func runYTDLP(
        arguments: [String],
        token: ProcessToken,
        onEvent: @escaping @Sendable (DownloadEvent) -> Void
    ) async throws -> [String] {
        let process = Process()
        process.executableURL = binaryManager.ytDlpURL
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let result: (Int32, String, [String]) = try await withCheckedThrowingContinuation { continuation in
            let collector = OutputCollector()

            let handleLine: @Sendable (String) -> Void = { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else {
                    return
                }

                onEvent(.log(line))

                if let range = line.range(of: "__YTDL_FILE__:") {
                    let path = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !path.isEmpty {
                        collector.appendOutputPath(path)
                    }
                }

                if let percent = DownloadRunner.extractProgress(from: line) {
                    onEvent(.progress(percent))
                }

                if let detail = DownloadRunner.extractStatusDetail(from: line) {
                    onEvent(.status(detail))
                }
            }

            outputPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    return
                }

                collector.appendChunk(chunk, handleLine: handleLine)
            }

            process.terminationHandler = { terminated in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                let remaining = outputPipe.fileHandleForReading.readDataToEndOfFile()

                let result = collector.finalize(remaining: remaining, handleLine: handleLine)

                continuation.resume(returning: (terminated.terminationStatus, result.output, result.paths))
            }

            do {
                try process.run()
                token.attach(process: process)
            } catch {
                outputPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }

        token.clear()

        if token.isCancelled {
            throw CancellationError()
        }

        guard result.0 == 0 else {
            let lines = result.1.split(separator: "\n").suffix(8).joined(separator: "\n")
            throw DownloadRunnerError.ytDlpFailed("yt-dlp a echoue.\n\(lines)")
        }

        return result.2
    }

    private static func extractProgress(from line: String) -> Double? {
        let pattern = "([0-9]{1,3}(?:\\.[0-9]+)?)%"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(location: 0, length: line.utf16.count)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: line) else {
            return nil
        }

        let value = String(line[valueRange]).replacingOccurrences(of: ",", with: ".")
        guard let rawPercent = Double(value) else {
            return nil
        }

        return min(max(rawPercent / 100.0, 0), 1)
    }

    private static func extractStatusDetail(from line: String) -> String? {
        if line.hasPrefix("[download]") {
            let detail = line.replacingOccurrences(of: "[download]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return nil
            }
            return detail
        }

        if line.hasPrefix("[Merger]") || line.hasPrefix("[ffmpeg]") {
            return line
        }

        return nil
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var mergedData = Data()
    private var partialLine = ""
    private var outputPaths: [String] = []

    func appendOutputPath(_ path: String) {
        lock.lock()
        outputPaths.append(path)
        lock.unlock()
    }

    func appendChunk(_ chunk: Data, handleLine: (String) -> Void) {
        guard let text = String(data: chunk, encoding: .utf8) else {
            lock.lock()
            mergedData.append(chunk)
            lock.unlock()
            return
        }

        lock.lock()
        mergedData.append(chunk)
        partialLine.append(text)
        let lines = partialLine.components(separatedBy: .newlines)
        partialLine = lines.last ?? ""
        lock.unlock()

        for line in lines.dropLast() {
            handleLine(line)
        }
    }

    func finalize(remaining: Data, handleLine: (String) -> Void) -> (output: String, paths: [String]) {
        lock.lock()
        mergedData.append(remaining)
        if let tailText = String(data: remaining, encoding: .utf8) {
            partialLine.append(tailText)
        }
        let trailing = partialLine
        partialLine = ""
        let output = String(decoding: mergedData, as: UTF8.self)
        lock.unlock()

        if !trailing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            handleLine(trailing)
        }

        lock.lock()
        let paths = outputPaths
        lock.unlock()

        return (output, paths)
    }
}
