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

    /// cwds currently being re-scanned via `reloadCwd` (drives a per-dir spinner).
    @Published private(set) var reloadingCwds = Set<String>()

    /// Cache of enriched sessions keyed by file URL, tagged with the file's
    /// mtime at enrichment time. A scan that finds the same URL with an
    /// unchanged mtime reuses the cached session — skipping the expensive
    /// re-read of title + message count. This makes both global and per-cwd
    /// refresh near-instant for files that haven't changed.
    private var cache: [URL: (mtime: Date, session: ChatSession)] = [:]

    /// Agents detected on this machine (for an "N agents discovered" line).
    var installedAgents: [String] {
        agents.filter(\.isInstalled).map(\.name)
    }

    private func agent(named name: String) -> Agent? {
        agents.first { $0.name == name }
    }

    /// Reuse the cached enriched session when the file is unchanged (same mtime);
    /// otherwise return the freshly-scanned (not-yet-enriched) session as-is.
    private func merged(_ scanned: ChatSession) -> ChatSession {
        if let hit = cache[scanned.primaryURL], hit.mtime == scanned.modifiedAt {
            return hit.session
        }
        return scanned
    }

    /// Record an enriched session in the cache under its current mtime.
    private func store(_ session: ChatSession) {
        cache[session.primaryURL] = (session.modifiedAt, session)
    }

    /// Full re-scan of all installed agents off the main thread. Unchanged
    /// files keep their cached enrichment; the cache is pruned to what still
    /// exists on disk.
    func reload() {
        isScanning = true
        let agents = self.agents
        DispatchQueue.global(qos: .userInitiated).async {
            let scanned = agents.filter(\.isInstalled).flatMap { $0.scan() }
            DispatchQueue.main.async {
                let merged = scanned.map(self.merged)
                self.groups = Self.group(merged)
                // Drop cache entries for files that no longer exist.
                let live = Set(scanned.map(\.primaryURL))
                self.cache = self.cache.filter { live.contains($0.key) }
                self.isScanning = false
            }
        }
    }

    /// Re-scan only the given cwd: pick up session files added/removed there and
    /// refresh this group — reusing cached enrichment for unchanged files, and
    /// eagerly enriching new/changed ones. Other groups are untouched.
    func reloadCwd(_ cwd: String) {
        guard !reloadingCwds.contains(cwd) else { return }
        reloadingCwds.insert(cwd)
        let agents = self.agents
        let snapshot = cache
        DispatchQueue.global(qos: .userInitiated).async {
            // Scanning is per-agent, not per-cwd, so scan then keep this cwd.
            let scanned = agents
                .filter(\.isInstalled)
                .flatMap { $0.scan() }
                .filter { $0.cwd == cwd }

            // Reuse cache for unchanged files; enrich the rest now.
            var refreshed: [ChatSession] = []
            for s in scanned {
                if let hit = snapshot[s.primaryURL], hit.mtime == s.modifiedAt {
                    refreshed.append(hit.session)
                } else if let agent = self.agent(named: s.agent) {
                    refreshed.append(agent.enrich(s))
                } else {
                    refreshed.append(s)
                }
            }
            refreshed.sort { $0.modifiedAt > $1.modifiedAt }

            DispatchQueue.main.async {
                self.reloadingCwds.remove(cwd)
                refreshed.forEach(self.store)
                if let gi = self.groups.firstIndex(where: { $0.cwd == cwd }) {
                    if refreshed.isEmpty {
                        self.groups.remove(at: gi) // all sessions gone → drop group
                    } else {
                        self.groups[gi] = ProjectGroup(cwd: cwd, sessions: refreshed)
                    }
                }
            }
        }
    }

    /// Enrich every not-yet-counted session in one cwd group (message count and,
    /// for some agents, the real title), off the main thread, then patch the
    /// results back in. Called when the user selects a directory, so only what's
    /// on screen is read.
    func ensureMessageCounts(forCwd cwd: String) {
        guard let group = groups.first(where: { $0.cwd == cwd }) else { return }
        let pending = group.sessions.filter { $0.messageCount == nil }
        guard !pending.isEmpty, !countingCwds.contains(cwd) else { return }

        countingCwds.insert(cwd)
        DispatchQueue.global(qos: .userInitiated).async {
            var enriched: [URL: ChatSession] = [:]
            for session in pending {
                guard let agent = self.agent(named: session.agent) else { continue }
                enriched[session.primaryURL] = agent.enrich(session)
            }
            DispatchQueue.main.async {
                self.apply(enriched, toCwd: cwd)
                enriched.values.forEach(self.store)
                self.countingCwds.remove(cwd)
            }
        }
    }

    /// Patch enriched sessions into the matching rows of one group.
    private func apply(_ enriched: [URL: ChatSession], toCwd cwd: String) {
        guard let gi = groups.firstIndex(where: { $0.cwd == cwd }) else { return }
        for si in groups[gi].sessions.indices {
            let url = groups[gi].sessions[si].primaryURL
            if let e = enriched[url] {
                groups[gi].sessions[si] = e
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
        cache.removeValue(forKey: session.primaryURL) // stop caching a deleted file
        return nil
    }
}
