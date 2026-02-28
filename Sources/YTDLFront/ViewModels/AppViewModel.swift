import AppKit
import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var queueItems: [DownloadItem] = []
    @Published var logs: [String] = []
    @Published var outputDirectory: URL

    @Published var isPreparing = false
    @Published var isQueueRunning = false
    @Published var currentYTDLPVersion: String = "-"
    @Published var availableUpdateVersion: String?
    @Published var statusLine: String = "Initialisation..."

    @Published var showUpdatePrompt = false
    @Published var updatePromptMessage = ""
    @Published var autoOpenInFinder = false {
        didSet {
            defaults.set(autoOpenInFinder, forKey: Keys.autoOpenInFinder)
        }
    }
    @Published var isLogPanelExpanded = false {
        didSet {
            defaults.set(isLogPanelExpanded, forKey: Keys.isLogPanelExpanded)
        }
    }

    private let binaryManager: BinaryManager
    private let updateService: UpdateService
    private let downloadRunner: DownloadRunner
    private let defaults = UserDefaults.standard

    private var queueTask: Task<Void, Never>?
    private var processTokens: [UUID: ProcessToken] = [:]
    private var didBootstrap = false

    var queuedCount: Int {
        queueItems.filter { $0.state == .queued }.count
    }

    var totalCount: Int {
        queueItems.count
    }

    var runningCount: Int {
        queueItems.filter { $0.state == .running }.count
    }

    var completedCount: Int {
        queueItems.filter { $0.state == .completed }.count
    }

    var failedCount: Int {
        queueItems.filter { $0.state == .failed }.count
    }

    var cancelledCount: Int {
        queueItems.filter { $0.state == .cancelled }.count
    }

    var canClearFinished: Bool {
        queueItems.contains { $0.state == .completed || $0.state == .failed || $0.state == .cancelled }
    }

    var progressSummary: Double {
        guard !queueItems.isEmpty else {
            return 0
        }

        let finished = queueItems.filter { $0.state == .completed || $0.state == .failed || $0.state == .cancelled }.count
        return Double(finished) / Double(queueItems.count)
    }

    var hasFailedItems: Bool {
        queueItems.contains { $0.state == .failed }
    }

    init(
        binaryManager: BinaryManager = BinaryManager(),
        updateService: UpdateService = UpdateService()
    ) {
        self.binaryManager = binaryManager
        self.updateService = updateService
        self.downloadRunner = DownloadRunner(binaryManager: binaryManager)
        if let storedPath = defaults.string(forKey: Keys.outputDirectoryPath), !storedPath.isEmpty {
            self.outputDirectory = URL(fileURLWithPath: storedPath, isDirectory: true)
        } else {
            self.outputDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
        self.autoOpenInFinder = defaults.bool(forKey: Keys.autoOpenInFinder)
        self.isLogPanelExpanded = defaults.bool(forKey: Keys.isLogPanelExpanded)
    }

    func bootstrapIfNeeded() async {
        guard !didBootstrap else {
            return
        }

        didBootstrap = true
        isPreparing = true
        statusLine = "Preparation des binaires..."

        do {
            let status = try await binaryManager.prepareBinaries()
            appendLog("yt-dlp: \(status.ytDlpPath)")
            appendLog("ffmpeg: \(status.ffmpegPath)")
            appendLog("ffprobe: \(status.ffprobePath)")

            currentYTDLPVersion = try await readYTDLPVersion()
            statusLine = "Pret."
            appendLog("Version yt-dlp active: \(currentYTDLPVersion)")

            let result = try await updateService.checkForUpdate(currentVersion: currentYTDLPVersion)
            handleUpdateResult(result)
        } catch {
            statusLine = "Erreur initialisation"
            appendLog("Erreur initialisation: \(error.localizedDescription)")
        }

        isPreparing = false
    }

    func pasteFromClipboard() {
        if let pasted = NSPasteboard.general.string(forType: .string) {
            if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                inputText = pasted
            } else {
                inputText += "\n\(pasted)"
            }
        }
    }

    func enqueueLinks() {
        let links = inputText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !links.isEmpty else {
            appendLog("Aucun lien a ajouter.")
            return
        }

        var addedCount = 0
        for link in links {
            guard isValidVideoURL(link) else {
                appendLog("Lien ignore (invalide): \(link)")
                continue
            }
            queueItems.append(DownloadItem(urlString: link))
            addedCount += 1
        }

        inputText = ""
        appendLog("\(addedCount) lien(s) ajoute(s) a la file.")
        startQueueIfNeeded()
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputDirectory

        if panel.runModal() == .OK, let selected = panel.url {
            outputDirectory = selected
            defaults.set(selected.path, forKey: Keys.outputDirectoryPath)
            appendLog("Dossier de sortie: \(selected.path)")
        }
    }

    func openOutputFolder() {
        NSWorkspace.shared.open(outputDirectory)
    }

    func revealDownloadedFile(itemID: UUID) {
        guard let item = queueItems.first(where: { $0.id == itemID }),
              let outputPath = item.outputPath else {
            return
        }

        let fileURL = URL(fileURLWithPath: outputPath)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func copyFailedLinks() {
        let failedLinks = queueItems
            .filter { $0.state == .failed }
            .map(\.urlString)

        guard !failedLinks.isEmpty else {
            appendLog("Aucun lien en erreur a copier.")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(failedLinks.joined(separator: "\n"), forType: .string)
        appendLog("\(failedLinks.count) lien(s) en erreur copies dans le presse-papiers.")
    }

    func clearLogs() {
        logs.removeAll(keepingCapacity: true)
        appendLog("Journal nettoye.")
    }

    func checkForUpdatesNow() {
        Task {
            do {
                statusLine = "Verification des mises a jour..."
                let result = try await updateService.checkForUpdate(currentVersion: currentYTDLPVersion, force: true)
                handleUpdateResult(result)
                if case .upToDate = result {
                    statusLine = "Aucune mise a jour disponible"
                    appendLog("yt-dlp est deja a jour.")
                }
            } catch {
                appendLog("Echec verification MAJ: \(error.localizedDescription)")
            }
        }
    }

    func installPendingUpdate() {
        Task {
            do {
                statusLine = "Installation de la mise a jour yt-dlp..."
                let installedVersion = try await updateService.installPendingUpdate(to: binaryManager.ytDlpURL)
                currentYTDLPVersion = installedVersion
                availableUpdateVersion = nil
                statusLine = "Mise a jour installee"
                appendLog("yt-dlp mis a jour vers \(installedVersion)")
            } catch {
                appendLog("Echec installation MAJ: \(error.localizedDescription)")
                statusLine = "Echec mise a jour"
            }
        }
    }

    func cancel(itemID: UUID) {
        guard let index = queueItems.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        switch queueItems[index].state {
        case .queued:
            queueItems[index].state = .cancelled
            queueItems[index].detail = "Annule avant execution"
        case .running:
            processTokens[itemID]?.cancel()
            queueItems[index].state = .cancelled
            queueItems[index].detail = "Annulation demandee"
        default:
            break
        }
    }

    func retry(itemID: UUID) {
        guard let index = queueItems.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        queueItems[index].state = .queued
        queueItems[index].progress = 0
        queueItems[index].detail = "En attente"
        queueItems[index].outputPath = nil
        startQueueIfNeeded()
    }

    func remove(itemID: UUID) {
        if let token = processTokens[itemID] {
            token.cancel()
            processTokens[itemID] = nil
        }
        queueItems.removeAll { $0.id == itemID }
    }

    func clearFinished() {
        queueItems.removeAll { $0.state == .completed || $0.state == .failed || $0.state == .cancelled }
    }

    func retryFailedItems() {
        var retried = 0
        for index in queueItems.indices {
            if queueItems[index].state == .failed || queueItems[index].state == .cancelled {
                queueItems[index].state = .queued
                queueItems[index].progress = 0
                queueItems[index].detail = "En attente"
                queueItems[index].outputPath = nil
                retried += 1
            }
        }

        if retried > 0 {
            appendLog("\(retried) element(s) remis en file.")
            startQueueIfNeeded()
        }
    }

    private func startQueueIfNeeded() {
        guard queueTask == nil else {
            return
        }

        queueTask = Task {
            await processQueue()
        }
    }

    private func processQueue() async {
        isQueueRunning = true
        defer {
            queueTask = nil
            isQueueRunning = false
        }

        while let nextIndex = queueItems.firstIndex(where: { $0.state == .queued }) {
            let itemID = queueItems[nextIndex].id
            guard let remoteURL = URL(string: queueItems[nextIndex].urlString) else {
                queueItems[nextIndex].state = .failed
                queueItems[nextIndex].detail = "URL invalide"
                continue
            }

            let token = ProcessToken()
            processTokens[itemID] = token

            queueItems[nextIndex].state = .running
            queueItems[nextIndex].detail = "Telechargement..."
            queueItems[nextIndex].progress = 0

            appendLog("Debut: \(queueItems[nextIndex].urlString)")

            do {
                let result = try await downloadRunner.downloadVideo(
                    from: remoteURL,
                    outputDirectory: outputDirectory,
                    token: token,
                    onEvent: { [weak self] event in
                        guard let self else { return }
                        Task { @MainActor in
                            self.handle(event: event, for: itemID)
                        }
                    }
                )

                if let index = queueItems.firstIndex(where: { $0.id == itemID }) {
                    queueItems[index].state = .completed
                    queueItems[index].progress = 1
                    queueItems[index].detail = "Termine"
                    queueItems[index].outputPath = result.outputURL.path
                    appendLog("Termine: \(result.outputURL.lastPathComponent)")
                    if autoOpenInFinder {
                        NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
                    }
                }
            } catch is CancellationError {
                if let index = queueItems.firstIndex(where: { $0.id == itemID }) {
                    queueItems[index].state = .cancelled
                    queueItems[index].detail = "Annule"
                    appendLog("Annule: \(queueItems[index].urlString)")
                }
            } catch {
                if let index = queueItems.firstIndex(where: { $0.id == itemID }) {
                    queueItems[index].state = .failed
                    queueItems[index].detail = error.localizedDescription
                    appendLog("Erreur: \(error.localizedDescription)")
                }
            }

            processTokens[itemID] = nil
        }
    }

    private func handle(event: DownloadEvent, for itemID: UUID) {
        guard let index = queueItems.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        switch event {
        case .progress(let value):
            queueItems[index].progress = value
            queueItems[index].detail = "\(Int(value * 100))%"
        case .status(let detail):
            queueItems[index].detail = detail
        case .log(let line):
            if line.lowercased().contains("error") {
                appendLog("[\(shortID(itemID))] \(line)")
            }
        }
    }

    private func readYTDLPVersion() async throws -> String {
        let result = try await CommandLineTool.run(executableURL: binaryManager.ytDlpURL, arguments: ["--version"])
        guard result.exitCode == 0 else {
            return "-"
        }

        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleUpdateResult(_ result: UpdateCheckResult) {
        switch result {
        case .upToDate:
            availableUpdateVersion = nil
        case .available(let version):
            availableUpdateVersion = version
            updatePromptMessage = "Nouvelle version yt-dlp disponible: \(version). Installer maintenant ?"
            showUpdatePrompt = true
            appendLog("Mise a jour disponible: \(version)")
        }
    }

    private func isValidVideoURL(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(6))
    }

    private func appendLog(_ message: String) {
        let timestamp = Self.logDateFormatter.string(from: Date())
        logs.append("[\(timestamp)] \(message)")
        if logs.count > 400 {
            logs.removeFirst(logs.count - 400)
        }
    }

    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private enum Keys {
        static let outputDirectoryPath = "app.outputDirectoryPath"
        static let autoOpenInFinder = "app.autoOpenInFinder"
        static let isLogPanelExpanded = "app.isLogPanelExpanded"
    }
}
