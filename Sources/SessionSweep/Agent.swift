import Foundation

/// An AI agent application whose chat sessions live on disk. Add support for a
/// new agent by implementing this. (Named `Agent`, not `Provider`, to avoid
/// confusion with LLM/model providers — these are AI applications.)
protocol Agent {
    /// Display name, e.g. "Kiro".
    var name: String { get }
    /// Whether this agent is installed on the machine (drives auto-discovery).
    var isInstalled: Bool { get }
    /// Scan and return every session this agent has stored.
    /// `messageCount` may be left nil here when counting is expensive;
    /// `countMessages(for:)` fills it in on demand.
    func scan() -> [ChatSession]
    /// Count user + assistant messages for one session. Potentially slow
    /// (reads the full conversation file), so callers run it off-main and
    /// only when the session is about to be shown.
    func countMessages(for session: ChatSession) -> Int
}

// MARK: - Kiro

/// Kiro CLI stores each session as a bundle of files under
/// `~/.kiro/sessions/cli/`:
///   {sid}.json    — metadata (cwd, title, created_at, updated_at)
///   {sid}.jsonl   — conversation event stream (the bulk of the size)
///   {sid}.lock    — process lock, present while a process holds the session
///   {sid}.history — command history (interactive chat only)
///   {sid}/        — occasional per-session subdirectory
///
/// The `.json` `cwd` field is the sole cwd↔session mapping; there is no index.
struct KiroAgent: Agent {
    let name = "Kiro"

    private var sessionsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kiro/sessions/cli", isDirectory: true)
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: sessionsDir.path)
    }

    func scan() -> [ChatSession] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        // Group every entry by its session id (the file-name stem).
        var bundles: [String: [URL]] = [:]
        for url in entries {
            let sid = url.deletingPathExtension().lastPathComponent
            bundles[sid, default: []].append(url)
        }

        // A session exists only if it has a `.json` metadata file.
        return bundles.compactMap { sid, urls in
            parse(sid: sid, urls: urls)
        }
    }

    private func parse(sid: String, urls: [URL]) -> ChatSession? {
        guard let jsonURL = urls.first(where: { $0.pathExtension == "json" }) else {
            return nil // no metadata → not a real session bundle
        }
        guard let data = try? Data(contentsOf: jsonURL),
              let meta = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let cwd = (meta["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "(unknown)"
        let title = Self.cleanTitle(meta["title"] as? String, sid: sid)

        // Sum the size of every file in the bundle; track newest mtime.
        var totalSize: Int64 = 0
        var newest = Date.distantPast
        for url in urls {
            let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            totalSize += Int64(v?.fileSize ?? 0)
            if let m = v?.contentModificationDate, m > newest { newest = m }
        }

        let lockURL = urls.first { $0.pathExtension == "lock" }
        let locked = lockURL.map(Self.isLockLive) ?? false

        return ChatSession(
            id: sid,
            agent: name,
            cwd: cwd,
            title: title,
            messageCount: nil, // counting jsonl lines is slow; done lazily on demand
            fileSize: totalSize,
            modifiedAt: newest,
            locked: locked,
            primaryURL: jsonURL,
            fileURLs: urls
        )
    }

    /// Count messages by streaming the `.jsonl` event log and tallying the
    /// `Prompt` (user) and `AssistantMessage` events. Tool results and
    /// compaction events are excluded — they aren't conversation messages.
    func countMessages(for session: ChatSession) -> Int {
        guard let jsonlURL = session.fileURLs.first(where: { $0.pathExtension == "jsonl" }),
              let content = try? String(contentsOf: jsonlURL, encoding: .utf8)
        else { return 0 }

        var count = 0
        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            switch obj["kind"] as? String {
            case "Prompt", "AssistantMessage": count += 1
            default: break
            }
        }
        return count
    }

    /// True only if the lock exists AND its PID is a live process.
    /// A crashed agent leaves a stale lock, so we verify the PID rather than
    /// trusting mere file existence (avoids false "in use" on dead sessions).
    private static func isLockLive(_ lockURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: lockURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = obj["pid"] as? Int32
        else { return false }
        // signal 0 = existence check, doesn't actually signal the process.
        return kill(pid, 0) == 0
    }

    /// Kiro occasionally stores a raw tool-result JSON blob as the title
    /// (e.g. `{"content":[{"type":"text","text":"<untrusted_content_…>…"}]}`).
    /// Recover readable text when we can, strip noise wrappers, and fall back
    /// to a friendly placeholder so the list never shows JSON soup.
    static func cleanTitle(_ raw: String?, sid: String) -> String {
        // Short id suffix so otherwise-blank rows stay distinguishable.
        let shortId = String(sid.prefix(8))
        let placeholder = "(untitled · \(shortId))"

        guard var t = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
            return placeholder
        }

        // If it parses as the content-array shape, pull the first text part.
        if t.hasPrefix("{"), let data = t.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let parts = obj["content"] as? [[String: Any]] {
            let text = parts
                .compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }
                .first
            t = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? t
        }

        // Drop a leading `<untrusted_content_…>` guard marker if present.
        if t.hasPrefix("<untrusted_content_"), let close = t.firstIndex(of: ">") {
            t = String(t[t.index(after: close)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Still JSON-looking or empty → unusable; show a stable placeholder.
        if t.isEmpty || t.hasPrefix("{") || t.hasPrefix("[") {
            return placeholder
        }

        // Collapse to a single line and clamp length for the table.
        let oneLine = t.split(whereSeparator: \.isNewline).joined(separator: " ")
        return oneLine.count > 80 ? String(oneLine.prefix(80)) + "…" : oneLine
    }
}

// MARK: - Claude Code

/// Claude Code stores sessions as `~/.claude/projects/<encoded-cwd>/<uuid>.jsonl`.
/// The real cwd lives inside the file, so we read it from the contents rather
/// than decoding the directory name (which is lossy when the path contains `-`).
struct ClaudeCodeAgent: Agent {
    let name = "Claude Code"

    private var projectsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: projectsRoot.path)
    }

    func scan() -> [ChatSession] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [ChatSession] = []
        for dir in projectDirs {
            let isDir = (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }

            // Only `.jsonl` files directly under the project dir (skip memory/ etc.).
            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                if let s = parse(file: file) {
                    result.append(s)
                }
            }
        }
        return result
    }

    private func parse(file: URL) -> ChatSession? {
        let v = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize = Int64(v?.fileSize ?? 0)
        let modified = v?.contentModificationDate ?? .distantPast

        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let lines = content.split(separator: "\n").map(String.init)
        guard !lines.isEmpty else { return nil }

        var cwd: String?
        var sessionId: String?
        var aiTitle: String?
        var firstUserText: String?
        var messageCount = 0

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if cwd == nil, let c = obj["cwd"] as? String { cwd = c }
            if sessionId == nil, let s = obj["sessionId"] as? String { sessionId = s }

            switch obj["type"] as? String {
            case "ai-title":
                if let t = obj["aiTitle"] as? String { aiTitle = t }
            case "user":
                messageCount += 1
                if firstUserText == nil { firstUserText = Self.extractText(from: obj["message"]) }
            case "assistant":
                messageCount += 1
            default:
                break
            }
        }

        let title = aiTitle
            ?? firstUserText?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60).description
            ?? file.deletingPathExtension().lastPathComponent

        return ChatSession(
            id: sessionId ?? file.deletingPathExtension().lastPathComponent,
            agent: name,
            cwd: cwd ?? "(unknown)",
            title: title.isEmpty ? "(untitled)" : title,
            messageCount: messageCount,
            fileSize: fileSize,
            modifiedAt: modified,
            locked: false,
            primaryURL: file,
            fileURLs: [file]
        )
    }

    /// Claude Code files are read in full during `scan`, so the count is
    /// already known; recompute from the file as a fallback if it was nil.
    func countMessages(for session: ChatSession) -> Int {
        if let n = session.messageCount { return n }
        return parse(file: session.primaryURL)?.messageCount ?? 0
    }

    /// Extract plain text from a `message` field (content may be a string or an array).
    private static func extractText(from message: Any?) -> String? {
        guard let msg = message as? [String: Any] else { return nil }
        if let s = msg["content"] as? String { return s }
        if let arr = msg["content"] as? [[String: Any]] {
            for part in arr where (part["type"] as? String) == "text" {
                if let t = part["text"] as? String { return t }
            }
        }
        return nil
    }
}
