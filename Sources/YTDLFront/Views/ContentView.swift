import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                metricsStrip
                inputPanel
                queuePanel
                logPanel
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, 24)
        }
        .frame(minWidth: 980, minHeight: 760)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("Video Downloader")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("V2")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(8)
                Spacer()
            }

            Text("Colle une ou plusieurs URLs, la file traite une video a la fois pour fiabilite max sur anciens Mac.")
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Text("yt-dlp: \(viewModel.currentYTDLPVersion)")
                    .font(.callout)
                if let version = viewModel.availableUpdateVersion {
                    Text("MAJ dispo: \(version)")
                        .font(.callout)
                        .foregroundColor(.orange)
                }
                Spacer()
                Button("Verifier les mises a jour") {
                    viewModel.checkForUpdatesNow()
                }
                .disabled(viewModel.isPreparing)
            }

            Text(viewModel.statusLine)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var metricsStrip: some View {
        HStack(spacing: 10) {
            MetricPill(title: "Total", value: "\(viewModel.totalCount)", tint: .gray)
            MetricPill(title: "En attente", value: "\(viewModel.queuedCount)", tint: .secondary)
            MetricPill(title: "En cours", value: "\(viewModel.runningCount)", tint: .blue)
            MetricPill(title: "Termines", value: "\(viewModel.completedCount)", tint: .green)
            MetricPill(title: "Erreurs", value: "\(viewModel.failedCount)", tint: .red)
            MetricPill(title: "Annules", value: "\(viewModel.cancelledCount)", tint: .orange)
            Spacer()
        }
    }

    private var inputPanel: some View {
        GroupBox(label: Text("Liens video")) {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $viewModel.inputText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )

                HStack {
                    Button("Coller") {
                        viewModel.pasteFromClipboard()
                    }
                    .disabled(viewModel.isPreparing)

                    Button("Ajouter a la file") {
                        viewModel.enqueueLinks()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.isPreparing || viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()

                    Text("Sortie: \(viewModel.outputDirectory.path)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.callout)

                    Button("Choisir...") {
                        viewModel.chooseOutputFolder()
                    }
                    .disabled(viewModel.isPreparing)

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
                    Text("\(viewModel.totalCount) element(s)")
                        .font(.callout)
                        .foregroundColor(.secondary)

                    if viewModel.totalCount > 0 {
                        ProgressView(value: viewModel.progressSummary)
                            .frame(width: 180)
                            .controlSize(.small)
                    }

                    Spacer()

                    if viewModel.isQueueRunning {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button("Retenter les erreurs") {
                        viewModel.retryFailedItems()
                    }
                    .disabled(!viewModel.hasFailedItems)

                    Button("Copier liens en erreur") {
                        viewModel.copyFailedLinks()
                    }
                    .disabled(!viewModel.hasFailedItems)

                    Button("Vider termines") {
                        viewModel.clearFinished()
                    }
                    .disabled(!viewModel.canClearFinished)
                }

                List(viewModel.queueItems) { item in
                    QueueRow(
                        item: item,
                        onCancel: { viewModel.cancel(itemID: item.id) },
                        onRetry: { viewModel.retry(itemID: item.id) },
                        onRemove: { viewModel.remove(itemID: item.id) },
                        onReveal: { viewModel.revealDownloadedFile(itemID: item.id) }
                    )
                }
                .frame(minHeight: 300)
            }
            .padding(.top, 2)
        }
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.isLogPanelExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.isLogPanelExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Journal")
                        .font(.headline)
                    Spacer()
                    Text("\(viewModel.logs.count) ligne(s)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if viewModel.isLogPanelExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Spacer()
                        Button("Nettoyer") {
                            viewModel.clearLogs()
                        }
                    }

                    ScrollView {
                        Text(viewModel.logs.joined(separator: "\n"))
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120)
                }
                .padding(12)
            }
        }
        .background(Color.secondary.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct MetricPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.08))
        .cornerRadius(10)
    }
}

private struct QueueRow: View {
    let item: DownloadItem
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(item.state.label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(statusColor)
                Text(item.urlString)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }

            ProgressView(value: item.state == .completed ? 1 : item.progress)
                .controlSize(.small)

            HStack {
                Text(item.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                if item.state == .completed, item.outputPath != nil {
                    Button("Afficher", action: onReveal)
                        .buttonStyle(.link)
                }
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
