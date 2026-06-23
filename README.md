# SessionSweep

**Chat session manager for your AI agents.**

SessionSweep auto-discovers the AI coding agents installed on your Mac (Kiro, Claude Code, …), groups their chat sessions by working directory, and lets you browse, sort, and clean them up — reclaiming disk space and keeping
your session history tidy.

A native SwiftUI app. Builds with just the **Command Line Tools** — no Xcode required.

## Features

- **Auto-discovery** — finds installed agents and scans their on-disk sessions. Agents are peers; add a new one by implementing the `Agent` protocol.
- **Grouped by working directory** — every `cwd` you've used an agent in, sorted by most recent activity, with per-directory session count and size.
- **Session details** — title, source agent, message count (lazily counted on selection so launch stays instant), size, last-modified, and session ID.
- **Sortable columns** — click any header to sort; e.g. by size to find the biggest sessions to clean.
- **Safe cleanup** — permanent delete (single or multi-select) always behind a confirmation dialog. Sessions held by a **running** agent are lock-detected and protected from deletion.
- **Quick navigation** — "Open in Finder" for a directory, "Reveal Files in Finder" and "Copy Session ID" per session.

### Supported agents

| Agent | Session location |
|-------|------------------|
| Kiro | `~/.kiro/sessions/cli/` |
| Claude Code | `~/.claude/projects/<encoded-cwd>/*.jsonl` |

SessionSweep is **read-only except for deletion** — it never modifies session content, and no data leaves your Mac.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools (`xcode-select --install`) — provides `swift`

## Installation (build from source)

```bash
git clone <repo-url> session-manager
cd session-manager

# Build, package, and install into /Applications in one step
./scripts/install.sh
```

`install.sh` builds the app, quits any running copy, installs it to
`/Applications`, and refreshes the icon cache. Use `./scripts/install.sh --user`
to install into `~/Applications` instead (no `sudo`).

Prefer to just build without installing?

```bash
./scripts/build-app.sh release   # produces build/SessionSweep.app
open build/SessionSweep.app
```

> **Note:** the app is ad-hoc signed, not Apple-notarized. If you copy the
> `.app` to another Mac, Gatekeeper will block the first launch — right-click
> the app and choose **Open**, then confirm once.

### Development

```bash
swift build          # debug build
swift run            # build & run from the terminal
```

App entry point is `Sources/SessionSweep/SessionSweepApp.swift`.

## Project layout

```
Package.swift                 SPM manifest (target: SessionSweep)
Sources/SessionSweep/
  SessionSweepApp.swift        @main app + About panel
  ContentView.swift            split view (sidebar + detail)
  SidebarView.swift            cwd groups + discovery summary
  SessionListView.swift        session table, sorting, delete, Finder actions
  SessionStore.swift           aggregates agents, lazy message counting
  Agent.swift                  Agent protocol + Kiro/Claude Code implementations
  Models.swift                 ChatSession, ProjectGroup
scripts/
  build-app.sh                 build + package into .app
  make-icon.swift              render the 1024px icon (AppKit)
  make-icns.sh                 PNG → multi-size .icns
```

## License

[MIT](LICENSE)
