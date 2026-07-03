import SwiftUI

/// Left column: every working directory that has sessions, grouped and sorted
/// by most recent activity. Shows a per-cwd session count and total size.
struct SidebarView: View {
    @EnvironmentObject var store: SessionStore
    @Binding var selectedCwd: String?

    var body: some View {
        VStack(spacing: 0) {
            // Fixed discovery summary — stays put while the list scrolls.
            // Fixed height matches the detail pane's header so dividers align.
            header
                .padding(.horizontal, 12)
                .frame(height: Layout.headerHeight, alignment: .topLeading)
            Divider()

            List(selection: $selectedCwd) {
                ForEach(store.groups) { group in
                    SidebarRow(group: group)
                        .tag(group.cwd)
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
    }

    private var header: some View {
        let agents = store.installedAgents
        let totalSessions = store.groups.reduce(0) { $0 + $1.sessions.count }
        let totalSize = store.groups.reduce(Int64(0)) { $0 + $1.totalSize }
        let orphanCount = store.groups.filter { !$0.cwdExists }.count
        return VStack(alignment: .leading, spacing: 6) {
            // Row 1: "Discovered" label + rescan button. Keeping the button on
            // its own line means it never collides with long agent names.
            HStack(spacing: 6) {
                Image(systemName: "sparkle.magnifyingglass")
                Text("Discovered")
                Spacer(minLength: 4)
                Button {
                    store.reload()
                } label: {
                    if store.isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.body)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(store.isScanning)
                .help("Rescan all agents")
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)

            // Row 2: the agent names as tags.
            if agents.isEmpty {
                Text("No AI agents found")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: 6) {
                    ForEach(agents, id: \.self) { agent in
                        Text(agent)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
            }

            // Row 3: totals.
            Text("\(totalSessions) sessions · \(totalSize.humanSize) · \(store.groups.count) dirs")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if orphanCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "folder.badge.questionmark")
                    Text("\(orphanCount) orphaned (directory deleted)")
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
        }
        .textCase(nil)
        .padding(.top, 2)
    }
}

private struct SidebarRow: View {
    let group: ProjectGroup

    private var isOrphan: Bool { !group.cwdExists }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                // Orphan (deleted cwd) gets a distinct icon + amber tint.
                Image(systemName: isOrphan ? "folder.badge.questionmark" : "folder")
                    .foregroundStyle(isOrphan ? .orange : .secondary)
                Text(group.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isOrphan {
                    Text("missing")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                }
                Spacer()
                Text("\(group.sessions.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(group.cwd)
                .font(.caption2)
                .foregroundStyle(isOrphan ? Color.orange.opacity(0.7) : Color.secondary.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.head)
        }
        .help(isOrphan ? "Directory no longer exists — sessions are orphaned" : group.cwd)
        .padding(.vertical, 2)
    }
}
