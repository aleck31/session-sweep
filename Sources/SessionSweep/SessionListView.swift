import SwiftUI

/// Right column: the sessions inside one cwd, with per-row delete and a
/// multi-select batch delete. Deletion is permanent and always confirmed.
struct SessionListView: View {
    @EnvironmentObject var store: SessionStore
    let group: ProjectGroup

    @State private var selection = Set<ChatSession.ID>()
    @State private var pendingDelete: [ChatSession] = []
    @State private var showConfirm = false
    @State private var errorMessage: String?

    // Click a column header to sort. Default: most recently modified first.
    @State private var sortOrder = [KeyPathComparator(\ChatSession.modifiedAt, order: .reverse)]

    /// The group's sessions arranged by the current header sort.
    private var sortedSessions: [ChatSession] {
        group.sessions.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            table
        }
        .navigationTitle(group.displayName)
        .navigationSubtitle(group.cwd)
        .task(id: group.cwd) {
            // Count messages for this group as soon as it's shown (covers the
            // initial auto-selection, which doesn't fire onChange).
            store.ensureMessageCounts(forCwd: group.cwd)
        }
        .confirmationDialog(
            confirmTitle,
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive, action: performDelete)
            Button("Cancel", role: .cancel) { pendingDelete = [] }
        } message: {
            Text(confirmMessage)
        }
        .alert("Delete failed", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Header / batch actions

    private var headerBar: some View {
        HStack {
            Text("\(group.sessions.count) sessions · \(group.totalSize.humanSize)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                openCwdInFinder()
            } label: {
                Label("Open in Finder", systemImage: "folder")
            }
            .controlSize(.small)
            .disabled(!cwdExists)
            .help(cwdExists ? "Reveal \(group.cwd) in Finder" : "Directory no longer exists")
            Spacer()
            if !selection.isEmpty {
                Text("\(selection.count) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    requestDelete(selectedSessions())
                } label: {
                    Label("Delete Selected", systemImage: "trash")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Table

    private var table: some View {
        Table(sortedSessions, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Title", value: \.title) { session in
                HStack(spacing: 6) {
                    if session.locked {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.orange)
                            .help("In use by a running process")
                    }
                    Text(session.title)
                        .lineLimit(1)
                }
            }
            TableColumn("Agent", value: \.agent) { Text($0.agent).foregroundStyle(.secondary) }
                .width(min: 80, ideal: 100)
            TableColumn("Messages", sortUsing: KeyPathComparator(\ChatSession.messageCount)) { session in
                if let n = session.messageCount {
                    Text("\(n) msgs").monospacedDigit().foregroundStyle(.secondary)
                } else if store.countingCwds.contains(group.cwd) {
                    ProgressView().controlSize(.small)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .width(min: 80, ideal: 90)
            TableColumn("Size", value: \.fileSize) { Text($0.fileSize.humanSize).monospacedDigit() }
                .width(min: 70, ideal: 80)
            TableColumn("Modified", value: \.modifiedAt) { Text($0.modifiedAt, format: .dateTime.year().month().day().hour().minute()) }
                .width(min: 130, ideal: 150)
            TableColumn("Session ID", value: \.id) { session in
                Text(session.id.prefix(8))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .help("\(session.id)\n(right-click to copy)") // full UUID on hover
                    .contextMenu {
                        Button {
                            copyID(session.id)
                        } label: {
                            Label("Copy Session ID", systemImage: "doc.on.doc")
                        }
                    }
            }
            .width(min: 90, ideal: 100)
            TableColumn("") { session in
                Button {
                    requestDelete([session])
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Delete this session")
                .disabled(session.locked)
            }
            .width(36)
        }
        .contextMenu(forSelectionType: ChatSession.ID.self) { ids in
            if ids.count == 1, let id = ids.first {
                Button {
                    copyID(id)
                } label: {
                    Label("Copy Session ID", systemImage: "doc.on.doc")
                }
                if let session = group.sessions.first(where: { $0.id == id }) {
                    Button {
                        revealInFinder(session)
                    } label: {
                        Label("Reveal Files in Finder", systemImage: "folder")
                    }
                }
            }
            Button(role: .destructive) {
                let sessions = group.sessions.filter { ids.contains($0.id) }
                requestDelete(sessions)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: Clipboard

    private func copyID(_ id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)
    }

    // MARK: Finder

    /// Some cwds are gone (e.g. /private/tmp dirs) or unknown — guard the button.
    private var cwdExists: Bool {
        group.cwd != "(unknown)" && FileManager.default.fileExists(atPath: group.cwd)
    }

    /// Open this group's working directory in Finder.
    private func openCwdInFinder() {
        guard cwdExists else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: group.cwd))
    }

    /// Reveal a session's underlying file(s) in Finder, selected.
    private func revealInFinder(_ session: ChatSession) {
        NSWorkspace.shared.activateFileViewerSelecting(session.fileURLs)
    }

    // MARK: Delete flow

    private func selectedSessions() -> [ChatSession] {
        group.sessions.filter { selection.contains($0.id) }
    }

    private func requestDelete(_ sessions: [ChatSession]) {
        // Locked sessions cannot be removed; drop them up front.
        let deletable = sessions.filter { !$0.locked }
        guard !deletable.isEmpty else {
            errorMessage = "The selected session(s) are in use by a running process."
            return
        }
        pendingDelete = deletable
        showConfirm = true
    }

    private func performDelete() {
        var firstError: String?
        for session in pendingDelete {
            if let err = store.delete(session), firstError == nil {
                firstError = err
            }
        }
        selection.removeAll()
        pendingDelete = []
        store.reload()
        if let firstError { errorMessage = firstError }
    }

    private var confirmTitle: String {
        pendingDelete.count == 1
            ? "Delete this session permanently?"
            : "Delete \(pendingDelete.count) sessions permanently?"
    }

    private var confirmMessage: String {
        let size = pendingDelete.reduce(Int64(0)) { $0 + $1.fileSize }.humanSize
        return "This cannot be undone. \(size) will be freed."
    }
}
