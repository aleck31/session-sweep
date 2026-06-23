import Foundation

/// Aggregates every installed agent's sessions. All agents are peers —
/// registration order carries no priority; results are merged and then
/// grouped/sorted purely by cwd and recency.
final class SessionStore: ObservableObject {
    /// The registry of known agents. Append a new agent here to support it.
    /// Order is cosmetic only (a stable tie-breaker, nothing more).
    private let agents: [Agent] = [
        KiroAgent(),
        ClaudeCodeAgent(),
    ]

    @Published private(set) var groups: [ProjectGroup] = []
    @Published private(set) var isScanning = false

    /// cwds whose message counts are currently being computed in the background.
    @Published private(set) var countingCwds = Set<String>()

    /// Agents detected on this machine (for an "N agents discovered" line).
    var installedAgents: [String] {
        agents.filter(\.isInstalled).map(\.name)
    }

    private func agent(named name: String) -> Agent? {
        agents.first { $0.name == name }
    }

    /// Re-scan all installed agents off the main thread, then publish.
    func reload() {
        isScanning = true
        let agents = self.agents
        DispatchQueue.global(qos: .userInitiated).async {
            let sessions = agents
                .filter(\.isInstalled)
                .flatMap { $0.scan() }
            let grouped = Self.group(sessions)
            DispatchQueue.main.async {
                self.groups = grouped
                self.isScanning = false
            }
        }
    }

    /// Count messages for every not-yet-counted session in one cwd group,
    /// off the main thread, then patch the results back into `groups`. Called
    /// when the user selects a directory, so only what's on screen is read.
    func ensureMessageCounts(forCwd cwd: String) {
        guard let group = groups.first(where: { $0.cwd == cwd }) else { return }
        let pending = group.sessions.filter { $0.messageCount == nil }
        guard !pending.isEmpty, !countingCwds.contains(cwd) else { return }

        countingCwds.insert(cwd)
        DispatchQueue.global(qos: .userInitiated).async {
            var counts: [URL: Int] = [:]
            for session in pending {
                guard let agent = self.agent(named: session.agent) else { continue }
                counts[session.primaryURL] = agent.countMessages(for: session)
            }
            DispatchQueue.main.async {
                self.applyCounts(counts, toCwd: cwd)
                self.countingCwds.remove(cwd)
            }
        }
    }

    /// Patch computed counts into the matching sessions of one group.
    private func applyCounts(_ counts: [URL: Int], toCwd cwd: String) {
        guard let gi = groups.firstIndex(where: { $0.cwd == cwd }) else { return }
        for si in groups[gi].sessions.indices {
            let url = groups[gi].sessions[si].primaryURL
            if let n = counts[url] {
                groups[gi].sessions[si].messageCount = n
            }
        }
    }

    /// Group sessions by cwd; newest session first within a group, and groups
    /// ordered by their most recent activity.
    private static func group(_ sessions: [ChatSession]) -> [ProjectGroup] {
        var byCwd: [String: [ChatSession]] = [:]
        for s in sessions {
            byCwd[s.cwd, default: []].append(s)
        }
        return byCwd
            .map { cwd, items in
                ProjectGroup(cwd: cwd, sessions: items.sorted { $0.modifiedAt > $1.modifiedAt })
            }
            .sorted { $0.latestModified > $1.latestModified }
    }

    /// Permanently delete a session's files. Returns nil on success, or an
    /// error message. Refuses locked sessions (a live agent owns them).
    func delete(_ session: ChatSession) -> String? {
        if session.locked {
            return "Session is in use by a running process."
        }
        let fm = FileManager.default
        for url in session.fileURLs {
            do {
                try fm.removeItem(at: url)
            } catch {
                return "Failed to delete \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        return nil
    }
}
