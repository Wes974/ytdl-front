import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            inputPanel
            queuePanel
            logPanel
        }
        .padding(16)
        .frame(minWidth: 920, minHeight: 700)
        .onAppear {
            Task {
                await viewModel.bootstrapIfNeeded()
            }
        }
        .alert(isPresented: $viewModel.showUpdatePrompt) {
            Alert(
                title: Text("Mise a jour yt-dlp"),
                message: Text(viewModel.updatePromptMessage),
                primaryButton: .default(Text("Installer"), action: {
                    viewModel.installPendingUpdate()
                }),
                secondaryButton: .cancel(Text("Plus tard"))
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YTDLFront")
                .font(.title2).bold()
            Text("Telechargement video MP4 garanti avec file multi-liens (1 a la fois)")
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Text("yt-dlp: \(viewModel.currentYTDLPVersion)")
                if let version = viewModel.availableUpdateVersion {
                    Text("MAJ dispo: \(version)")
                        .foregroundColor(.orange)
                }
                Spacer()
                Button("Verifier les mises a jour") {
                    viewModel.checkForUpdatesNow()
                }
            }
            .font(.callout)

            Text(viewModel.statusLine)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var inputPanel: some View {
        GroupBox(label: Text("Liens video")) {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $viewModel.inputText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 110)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                HStack {
                    Button("Coller") {
                        viewModel.pasteFromClipboard()
                    }
                    Button("Ajouter a la file") {
                        viewModel.enqueueLinks()
                    }
                    .keyboardShortcut(.defaultAction)

                    Spacer()

                    Text("Sortie: \(viewModel.outputDirectory.path)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.callout)

                    Button("Choisir...") {
                        viewModel.chooseOutputFolder()
                    }
                    Button("Ouvrir") {
                        viewModel.openOutputFolder()
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private var queuePanel: some View {
        GroupBox(label: Text("File d'attente")) {
            VStack(spacing: 8) {
                HStack {
                    Text("\(viewModel.queueItems.count) element(s)")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                    if viewModel.isQueueRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("Vider termines") {
                        viewModel.clearFinished()
                    }
                }

                List(viewModel.queueItems) { item in
                    QueueRow(
                        item: item,
                        onCancel: { viewModel.cancel(itemID: item.id) },
                        onRetry: { viewModel.retry(itemID: item.id) },
                        onRemove: { viewModel.remove(itemID: item.id) }
                    )
                }
                .frame(minHeight: 260)
            }
            .padding(.top, 2)
        }
    }

    private var logPanel: some View {
        GroupBox(label: Text("Journal")) {
            ScrollView {
                Text(viewModel.logs.joined(separator: "\n"))
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120)
        }
    }
}

private struct QueueRow: View {
    let item: DownloadItem
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.state.label)
                    .font(.caption)
                    .foregroundColor(statusColor)
                Text(item.urlString)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }

            if item.state == .running || item.state == .completed {
                ProgressView(value: item.progress)
                    .controlSize(.small)
            }

            HStack {
                Text(item.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                if item.state == .running || item.state == .queued {
                    Button("Annuler", action: onCancel)
                        .buttonStyle(.link)
                }
                if item.state == .failed || item.state == .cancelled {
                    Button("Retenter", action: onRetry)
                        .buttonStyle(.link)
                }
                Button("Supprimer", action: onRemove)
                    .buttonStyle(.link)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch item.state {
        case .queued:
            return .gray
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        }
    }
}
