import SwiftUI

/// Root layout: a sidebar of cwd groups and a detail list of that group's sessions.
struct ContentView: View {
    @EnvironmentObject var store: SessionStore
    @State private var selectedCwd: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedCwd: $selectedCwd)
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
        } detail: {
            if let cwd = selectedCwd,
               let group = store.groups.first(where: { $0.cwd == cwd }) {
                SessionListView(group: group)
            } else {
                EmptyDetailView()
            }
        }
        .navigationTitle("SessionSweep")
        .onChange(of: store.groups) { _, groups in
            // Keep a valid selection after a rescan.
            if selectedCwd == nil || !groups.contains(where: { $0.cwd == selectedCwd }) {
                selectedCwd = groups.first?.cwd
            }
        }
        .onChange(of: store.isScanning) { _, scanning in
            // A rescan resets lazily-counted agents (e.g. Kiro) back to nil.
            // When it finishes, recompute counts for the directory in view so
            // the Messages column doesn't fall back to "—".
            if !scanning, let cwd = selectedCwd {
                store.ensureMessageCounts(forCwd: cwd)
            }
        }
    }
}

private struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text("Select a directory")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Pick a working directory on the left to view its chat sessions.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
