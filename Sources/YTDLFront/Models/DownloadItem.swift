import Foundation

enum DownloadState: String {
    case queued
    case running
    case completed
    case failed
    case cancelled

    var label: String {
        switch self {
        case .queued:
            return "En attente"
        case .running:
            return "En cours"
        case .completed:
            return "Termine"
        case .failed:
            return "Erreur"
        case .cancelled:
            return "Annule"
        }
    }
}

struct DownloadItem: Identifiable, Equatable {
    let id: UUID
    let urlString: String
    var state: DownloadState
    var progress: Double
    var detail: String
    var outputPath: String?

    init(urlString: String) {
        self.id = UUID()
        self.urlString = urlString
        self.state = .queued
        self.progress = 0
        self.detail = "En attente"
        self.outputPath = nil
    }
}
