import SwiftUI
import AppKit

@main
struct SessionSweepApp: App {
    @StateObject private var store = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 820, minHeight: 520)
                .onAppear { store.reload() }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {} // no "New" menu — nothing to create

            // Replace the default "About" with one carrying our description.
            CommandGroup(replacing: .appInfo) {
                Button("About SessionSweep") { showAboutPanel() }
            }

            // Replace the unhelpful default "SessionSweep Help" item.
            CommandGroup(replacing: .help) {
                Button("SessionSweep Help") { showAboutPanel() }
                    .keyboardShortcut("?", modifiers: .command)
            }
        }
    }
}

/// Show the standard macOS About panel populated with the app's name,
/// version, and a short description (rendered as the credits block).
@MainActor
private func showAboutPanel() {
    let description = """
    Chat session manager for your AI agents.

    SessionSweep auto-discovers the AI coding agents installed on \
    this Mac (Kiro, Claude Code, …), groups their chat sessions by \
    working directory, and lets you browse, sort, and clean them up — \
    reclaiming disk space and keeping your session history tidy.
    """

    let credits = NSAttributedString(
        string: description,
        attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
    )

    // Let the panel derive the version line from Info.plist itself — passing
    // .applicationVersion here would duplicate the auto-appended build string.
    NSApplication.shared.orderFrontStandardAboutPanel(options: [
        .applicationName: "SessionSweep",
        .credits: credits,
        .init(rawValue: "Copyright"): "A local utility · no data leaves your Mac",
    ])
    NSApplication.shared.activate(ignoringOtherApps: true)
}
