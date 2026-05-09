import Foundation

struct BinaryStatus {
    let ytDlpPath: String
    let ffmpegPath: String
    let ffprobePath: String
}

enum BinaryManagerError: LocalizedError {
    case missingGitHubAsset(String)
    case invalidResponse
    case unzipFailed
    case downloadedBinaryMissing(String)

    var errorDescription: String? {
        switch self {
        case .missingGitHubAsset(let name):
            return "Asset GitHub introuvable: \(name)."
        case .invalidResponse:
            return "Reponse reseau invalide."
        case .unzipFailed:
            return "Extraction ZIP impossible."
        case .downloadedBinaryMissing(let name):
            return "Binaire \(name) absent apres telechargement."
        }
    }
}

final class BinaryManager: @unchecked Sendable {
    private let fileManager = FileManager.default
    private let appName = "YTDLFront"

    lazy var appSupportDirectory: URL = {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(appName, isDirectory: true)
    }()

    lazy var binDirectory: URL = {
        appSupportDirectory.appendingPathComponent("bin", isDirectory: true)
    }()

    var ytDlpURL: URL {
        binDirectory.appendingPathComponent("yt-dlp")
    }

    var ffmpegURL: URL {
        binDirectory.appendingPathComponent("ffmpeg")
    }

    var ffprobeURL: URL {
        binDirectory.appendingPathComponent("ffprobe")
    }

    func prepareBinaries() async throws -> BinaryStatus {
        try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)

        try await ensureYTDLP()
        try await ensureFFmpeg()
        try await ensureFFprobe()

        return BinaryStatus(
            ytDlpPath: ytDlpURL.path,
            ffmpegPath: ffmpegURL.path,
            ffprobePath: ffprobeURL.path
        )
    }

    private func ensureYTDLP() async throws {
        if fileManager.fileExists(atPath: ytDlpURL.path) {
            try makeExecutable(ytDlpURL)
            return
        }

        if let bundled = bundledBinary(named: "yt-dlp_macos") ?? bundledBinary(named: "yt-dlp") {
            try copyBinary(from: bundled, to: ytDlpURL)
            return
        }

        try await downloadLatestYTDLP(to: ytDlpURL)
        try makeExecutable(ytDlpURL)
    }

    private func ensureFFmpeg() async throws {
        // Prefer bundled over cached so that an app update brings a refreshed ffmpeg
        // even when the previous version left a (possibly arch-mismatched) binary in
        // Application Support. yt-dlp can be auto-updated independently — ffmpeg
        // cannot, so the bundle is the source of truth.
        if let bundled = bundledBinary(named: "ffmpeg") {
            try refreshBinaryFromBundle(bundled: bundled, destination: ffmpegURL)
            return
        }

        if fileManager.fileExists(atPath: ffmpegURL.path) {
            try makeExecutable(ffmpegURL)
            return
        }

        try await downloadEvermeetBinary(named: "ffmpeg", destinationURL: ffmpegURL)
        try makeExecutable(ffmpegURL)
    }

    private func ensureFFprobe() async throws {
        if let bundled = bundledBinary(named: "ffprobe") {
            try refreshBinaryFromBundle(bundled: bundled, destination: ffprobeURL)
            return
        }

        if fileManager.fileExists(atPath: ffprobeURL.path) {
            try makeExecutable(ffprobeURL)
            return
        }

        try await downloadEvermeetBinary(named: "ffprobe", destinationURL: ffprobeURL)
        try makeExecutable(ffprobeURL)
    }

    private func refreshBinaryFromBundle(bundled: URL, destination: URL) throws {
        // Skip the copy when the cached file is byte-for-byte identical to the bundle,
        // so unchanged launches are O(stat) instead of O(80MB).
        if let bundledSize = try? bundled.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           let cachedSize = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           bundledSize == cachedSize,
           let bundledMtime = try? bundled.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           let cachedMtime = try? destination.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           bundledMtime == cachedMtime {
            try makeExecutable(destination)
            return
        }

        try copyBinary(from: bundled, to: destination)
    }

    private func bundledBinary(named name: String) -> URL? {
        guard let resources = Bundle.main.resourceURL else {
            return nil
        }

        let candidates = [
            resources.appendingPathComponent("bin").appendingPathComponent(name),
            resources.appendingPathComponent(name)
        ]

        return candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
    }

    private func copyBinary(from source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        try makeExecutable(destination)
    }

    private func makeExecutable(_ url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func downloadLatestYTDLP(to destinationURL: URL) async throws {
        let releaseURL = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!
        var request = URLRequest(url: releaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BinaryManagerError.invalidResponse
        }

        let decoder = JSONDecoder()
        let release = try decoder.decode(GitHubRelease.self, from: data)

        guard let asset = release.assets.first(where: { $0.name == "yt-dlp_macos" })
            ?? release.assets.first(where: { $0.name == "yt-dlp" }) else {
            throw BinaryManagerError.missingGitHubAsset("yt-dlp_macos")
        }

        let (binaryData, binaryResponse) = try await URLSession.shared.data(from: asset.browserDownloadURL)
        guard let http = binaryResponse as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BinaryManagerError.invalidResponse
        }

        try binaryData.write(to: destinationURL, options: [.atomic])
    }

    private func downloadEvermeetBinary(named toolName: String, destinationURL: URL) async throws {
        let zipURL = URL(string: "https://evermeet.cx/ffmpeg/getrelease/\(toolName)/zip")!
        let (zipData, response) = try await URLSession.shared.data(from: zipURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BinaryManagerError.invalidResponse
        }

        let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let zipPath = tempRoot.appendingPathComponent("\(toolName).zip")
        let unzipPath = tempRoot.appendingPathComponent("unzipped", isDirectory: true)
        try fileManager.createDirectory(at: unzipPath, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: tempRoot)
        }

        try zipData.write(to: zipPath, options: [.atomic])

        let unzipResult = try await CommandLineTool.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-o", zipPath.path, "-d", unzipPath.path]
        )
        guard unzipResult.exitCode == 0 else {
            throw BinaryManagerError.unzipFailed
        }

        let extracted = try findExtractedBinary(named: toolName, in: unzipPath)
        guard let binary = extracted else {
            throw BinaryManagerError.downloadedBinaryMissing(toolName)
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: binary, to: destinationURL)
    }

    private func findExtractedBinary(named name: String, in directory: URL) throws -> URL? {
        let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        while let next = enumerator?.nextObject() as? URL {
            if next.lastPathComponent == name {
                return next
            }
        }
        return nil
    }
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let assets: [Asset]
}
