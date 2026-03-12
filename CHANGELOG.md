# Changelog

All notable changes to Cosmodrome are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-03-12

First release. A native macOS terminal for developers running multiple AI agents in parallel.

### Added

#### Core
- **Metal renderer** -- single `MTKView` with viewport scissoring, shared glyph atlas, triple-buffered vertex data. Sub-4ms frame times.
- **SwiftTerm backend** -- VT parsing via SwiftTerm with `TerminalBackend` protocol for future swap to libghostty-vt.
- **kqueue PTY multiplexer** -- single I/O thread for all PTY file descriptors. Zero CPU when idle.
- **Agent detection** -- inline pattern matching for Claude Code, Aider, Codex, and Gemini. States: working, needsInput, error, inactive.
- **Model detection** -- passive detection of which LLM model is in use.
- **Project and session management** -- `@Observable` models, YAML configuration, project store.
- **Layout engine** -- grid and focus modes.
- **Configuration** -- YAML parsing for user and project config.
- **Completion actions** -- suggested next steps on task completion (never auto-triggered).

#### UI
- **Sidebar** -- SwiftUI project list with session thumbnails.
- **Status bar** -- agent state indicators, model display, fleet stats (working/idle/input/error counts + total cost + tasks).
- **Activity log overlay** (`Cmd+L`) -- full-screen timeline of agent events (files changed, commands run, errors, tasks). Filter by time window, event type, or session.
- **Fleet overview overlay** (`Cmd+Shift+F`) -- full-screen dashboard of all agents across all projects. Agent cards sorted by priority. Filter by state. Aggregate stats.
- **Command palette** (`Cmd+P`) for quick access to all actions.
- **Modal keybindings** -- normal + command mode with `Ctrl+Space` toggle and vim-style navigation.
- **Font zoom** -- `Cmd+=`/`Cmd+-`/`Cmd+0` for font size adjustment with persistence.
- **Theme system** -- dark, light, and custom YAML themes.
- **Idle prominence** -- thumbnails show idle duration with escalating color indicators.
- **OSC 777 notifications** -- terminal notification support with attention ring animation.
- **Native macOS notifications** for agent state changes.

#### Agent Integration
- **Claude Code hooks** -- deep integration via structured hooks (PreToolUse, PostToolUse, Notification, Stop). Structured parsing of `tool_input`/`tool_output` JSON (file paths, commands, exit codes, cost deltas). Hook events are authoritative when available.
- **Hook server** -- Unix socket IPC for structured agent lifecycle events.
- **CosmodromeHook binary** -- tiny binary reads JSON from stdin, forwards to hook socket.
- **Per-task cost tracking** -- cost delta calculated between task start and completion.
- **Fleet-wide cost aggregation** -- total cost, tasks completed, and files changed across all projects.

#### Infrastructure
- **MCP server** -- JSON-RPC 2.0 over stdio (`--mcp` flag). Tools: `list_projects`, `list_sessions`, `get_session_content`, `send_input`, `get_agent_states`, `focus_session`, `start_recording`, `stop_recording`, `get_fleet_stats`, `get_activity_log`.
- **Session recording** -- asciicast v2 format via `AsciicastRecorder` and `AsciicastPlayer`.
- **CLI control plane** -- `cosmoctl` binary for controlling a running Cosmodrome instance via Unix socket. Commands: `status`, `list-projects`, `list-sessions`, `focus`, `send`, `new-session`, `content`, `fleet-stats`, `activity`.
- **Control server** -- Unix socket at `$TMPDIR/cosmodrome-<uid>.control.sock`.
- **Port detection** -- detects listening ports from child processes, shows click-to-open badges.
- **Session persistence** -- saves project/session state and scrollback across restarts.
- **OSC 133 semantic prompt tracking** for shell integration.
- **Git worktree integration** for multi-branch workflows.
- **DMG distribution** -- `scripts/build-dmg.sh` creates a signed DMG installer.
- **Homebrew Cask** -- `brew install --cask cosmodrome`.
- **Release script** -- `scripts/release.sh` for tagging and preparing GitHub releases.
