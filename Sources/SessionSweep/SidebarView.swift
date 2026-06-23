import SwiftUI

/// Left column: every working directory that has sessions, grouped and sorted
/// by most recent activity. Shows a per-cwd session count and total size.
struct SidebarView: View {
    @EnvironmentObject var store: SessionStore
    @Binding var selectedCwd: String?

    var body: some View {
        List(selection: $selectedCwd) {
            Section {
                ForEach(store.groups) { group in
                    SidebarRow(group: group)
                        .tag(group.cwd)
                }
            } header: {
                header
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if store.isScanning && store.groups.isEmpty {
                ProgressView("Scanning…")
            } else if !store.isScanning && store.groups.isEmpty {
                ContentUnavailableView(
                    "No sessions found",
                    systemImage: "tray",
                    description: Text("No installed agent has any stored sessions.")
                )
            }
        }
    }

    private var header: some View {
        let agents = store.installedAgents
        let totalSessions = store.groups.reduce(0) { $0 + $1.sessions.count }
        let totalSize = store.groups.reduce(Int64(0)) { $0 + $1.totalSize }
        return VStack(alignment: .leading, spacing: 3) {
            // Reads as an auto-discovery status, not an app title: de-emphasized
            // (secondary, not bold) with an explicit "Discovered:" prefix.
            HStack(spacing: 4) {
                Image(systemName: "sparkle.magnifyingglass")
                Text(agents.isEmpty
                     ? "No AI agents discovered"
                     : "Discovered: \(agents.joined(separator: ", "))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text("\(totalSessions) sessions · \(totalSize.humanSize) · \(store.groups.count) dirs")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            // Separate the discovery summary from the directory list below.
            Divider()
                .padding(.top, 4)
        }
        .textCase(nil)
        .padding(.vertical, 2)
    }
}

private struct SidebarRow: View {
    let group: ProjectGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(group.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(group.sessions.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(group.cwd)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.vertical, 2)
        .help(group.cwd)
    }
}
