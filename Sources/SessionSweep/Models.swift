import Foundation

/// A single chat session (one bundle of files on disk).
/// Equatable/Hashable are synthesized over all fields (including
/// `messageCount`) so SwiftUI detects when a lazily-computed count arrives.
/// Row identity in the table comes from `id`, not equality.
struct ChatSession: Identifiable, Hashable {
    let id: String            // sessionId (falls back to the file name stem)
    let agent: String         // source agent, e.g. "Kiro" / "Claude Code"
    let cwd: String           // working directory this session belongs to
    let title: String         // display title
    var messageCount: Int?    // user + assistant messages; nil = not counted yet
    let fileSize: Int64        // total bytes of all files in this session
    let modifiedAt: Date      // last modification time
    let locked: Bool          // held by a live process (a running agent owns the lock)
    let primaryURL: URL       // primary file (.json / .jsonl), used as identity
    let fileURLs: [URL]       // every file to remove when deleting this session
}

/// A set of sessions grouped by their cwd.
struct ProjectGroup: Identifiable, Equatable {
    var id: String { cwd }
    let cwd: String
    var sessions: [ChatSession]

    /// Last path component, for a compact sidebar label.
    var displayName: String {
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty ? cwd : name
    }

    var totalSize: Int64 { sessions.reduce(0) { $0 + $1.fileSize } }
    var latestModified: Date { sessions.map(\.modifiedAt).max() ?? .distantPast }
}

extension Int64 {
    /// Human-readable file size.
    var humanSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
