import CryptoKit
import Foundation

enum UpdateCheckResult {
    case upToDate
    case available(String)
}

enum UpdateServiceError: LocalizedError {
    case noPendingUpdate
    case missingAsset(String)
    case invalidResponse
    case checksumMissing
    case checksumMismatch(expected: String, actual: String)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .noPendingUpdate:
            return "Aucune mise a jour en attente."
        case .missingAsset(let name):
            return "Asset manquant: \(name)."
        case .invalidResponse:
            return "Reponse distante invalide."
        case .checksumMissing:
            return "Checksum SHA-256 introuvable."
        case .checksumMismatch(let expected, let actual):
            return "Checksum invalide (attendu \(expected), obtenu \(actual))."
        case .verificationFailed:
            return "Le nouveau binaire yt-dlp ne repond pas correctement."
        }
    }
}

final class UpdateService: @unchecked Sendable {
    private let defaults = UserDefaults.standard
    private let updateCheckInterval: TimeInterval = 24 * 60 * 60

    private let lastCheckKey = "ytdlfront.lastUpdateCheck"
    private var pendingUpdate: PendingUpdate?

    func shouldCheckAutomatically(now: Date = Date()) -> Bool {
        guard let lastCheck = defaults.object(forKey: lastCheckKey) as? Date else {
            return true
        }
        return now.timeIntervalSince(lastCheck) >= updateCheckInterval
    }

    func checkForUpdate(currentVersion: String?, force: Bool = false) async throws -> UpdateCheckResult {
        if !force && !shouldCheckAutomatically() {
            return .upToDate
        }

        let release = try await fetchLatestRelease()
        defaults.set(Date(), forKey: lastCheckKey)

        let normalizedCurrent = (currentVersion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRemote = release.tagName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isRemoteVersionNewer(remote: normalizedRemote, current: normalizedCurrent) else {
            pendingUpdate = nil
            return .upToDate
        }

        guard let ytDlpAsset = release.assets.first(where: { $0.name == "yt-dlp_macos" })
            ?? release.assets.first(where: { $0.name == "yt-dlp" }) else {
            throw UpdateServiceError.missingAsset("yt-dlp_macos")
        }

        guard let checksumAsset = release.assets.first(where: { $0.name == "SHA2-256SUMS" }) else {
            throw UpdateServiceError.missingAsset("SHA2-256SUMS")
        }

        let checksumText = try await fetchText(from: checksumAsset.browserDownloadURL)
        guard let checksum = parseChecksum(from: checksumText, forAssetName: ytDlpAsset.name) else {
            throw UpdateServiceError.checksumMissing
        }

        pendingUpdate = PendingUpdate(
            version: normalizedRemote,
            binaryURL: ytDlpAsset.browserDownloadURL,
            expectedSHA256: checksum
        )

        return .available(normalizedRemote)
    }

    func installPendingUpdate(to destinationURL: URL) async throws -> String {
        guard let update = pendingUpdate else {
            throw UpdateServiceError.noPendingUpdate
        }

        let (binaryData, response) = try await URLSession.shared.data(from: update.binaryURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UpdateServiceError.invalidResponse
        }

        let computedChecksum = sha256(for: binaryData)
        guard computedChecksum.caseInsensitiveCompare(update.expectedSHA256) == .orderedSame else {
            throw UpdateServiceError.checksumMismatch(expected: update.expectedSHA256, actual: computedChecksum)
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let backupURL = destinationURL.deletingLastPathComponent().appendingPathComponent("yt-dlp.backup")
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.copyItem(at: destinationURL, to: backupURL)
        }

        let tempURL = destinationURL.deletingLastPathComponent().appendingPathComponent("yt-dlp.new")
        if fileManager.fileExists(atPath: tempURL.path) {
            try fileManager.removeItem(at: tempURL)
        }

        do {
            try binaryData.write(to: tempURL, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempURL.path)

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: tempURL, to: destinationURL)

            let verification = try await CommandLineTool.run(executableURL: destinationURL, arguments: ["--version"])
            guard verification.exitCode == 0 else {
                throw UpdateServiceError.verificationFailed
            }

            pendingUpdate = nil

            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }

            return verification.output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: destinationURL)
            }

            if fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.moveItem(at: backupURL, to: destinationURL)
            }

            if fileManager.fileExists(atPath: tempURL.path) {
                try? fileManager.removeItem(at: tempURL)
            }

            throw error
        }
    }

    private func fetchLatestRelease() async throws -> GitHubReleaseResponse {
        let releaseURL = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!
        var request = URLRequest(url: releaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UpdateServiceError.invalidResponse
        }

        return try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
    }

    private func fetchText(from url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UpdateServiceError.invalidResponse
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func parseChecksum(from checksumFile: String, forAssetName assetName: String) -> String? {
        for line in checksumFile.split(separator: "\n") {
            let columns = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).filter { !$0.isEmpty }
            guard columns.count >= 2 else {
                continue
            }

            let hash = String(columns[0])
            let fileName = String(columns[1]).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            if fileName == assetName {
                return hash
            }
        }
        return nil
    }

    private func sha256(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func isRemoteVersionNewer(remote: String, current: String) -> Bool {
        if current.isEmpty {
            return true
        }

        let remoteParts = remote.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        let currentParts = current.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }

        if remoteParts.isEmpty || currentParts.isEmpty {
            return remote != current
        }

        let maxCount = max(remoteParts.count, currentParts.count)
        for index in 0..<maxCount {
            let left = index < remoteParts.count ? remoteParts[index] : 0
            let right = index < currentParts.count ? currentParts[index] : 0
            if left > right {
                return true
            }
            if left < right {
                return false
            }
        }

        return false
    }
}

private struct PendingUpdate {
    let version: String
    let binaryURL: URL
    let expectedSHA256: String
}

private struct GitHubReleaseResponse: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}
