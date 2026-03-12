# Changelog

All notable changes to Cosmodrome are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.2.0] - 2026-03-12

### Added
- **Activity Log overlay** -- full-screen timeline of agent events (files changed, commands run, errors, tasks) across all projects. Filter by time window, event type, or session. Toggle with `Cmd+L` or command mode `a`.
- **Fleet Overview overlay** -- full-screen dashboard of all agents across all projects. Agent cards sorted by priority. Filter by state. Toggle with `Cmd+Shift+F` or command mode `g`.
- **Per-task cost tracking** -- cost delta calculated between task start and completion. Average and last task cost exposed in session stats.
- **Fleet-wide cost aggregation** -- total cost, tasks completed, and files changed across all projects.
- **Claude Code hooks deep integration** -- structured parsing of `tool_input`/`tool_output` JSON (file paths, commands, exit codes, cost deltas). Hook events are authoritative when available.
- **`get_activity_log` MCP tool** -- query activity timeline with time window, session, and category filters.
- **`get_fleet_stats` MCP tool** -- fleet-wide statistics via MCP.
- **`cosmoctl activity` CLI command** -- query activity log from the command line with `--since`, `--session`, `--category` flags.
- **`cosmoctl fleet-stats` CLI command** -- fleet statistics from the command line.
- **DMG distribution** -- `scripts/build-dmg.sh` creates a signed DMG installer.
- **Homebrew Cask** -- `brew install --cask cosmodrome`.
- **Release script** -- `scripts/release.sh` for tagging and preparing GitHub releases.
- **Font zoom** -- `Cmd+=`/`Cmd+-`/`Cmd+0` for font size adjustment with persistence.
- **Idle prominence** -- thumbnails show idle duration with escalating color indicators.

## [1.1.0] - 2026-03-11

### Added
- **MCP server** -- JSON-RPC 2.0 over stdio. Tools: `list_projects`, `list_sessions`, `get_session_content`, `send_input`, `get_agent_states`, `focus_session`, `start_recording`, `stop_recording`. Enable with `--mcp` flag.
- **Session recording** -- asciicast v2 format via `AsciicastRecorder` and `AsciicastPlayer`.
- **CLI control plane** -- `cosmoctl` binary for controlling a running Cosmodrome instance via Unix socket. Commands: `status`, `list-projects`, `list-sessions`, `focus`, `send`, `new-session`, `content`.
- **Control server** -- Unix socket server at `$TMPDIR/cosmodrome-<uid>.control.sock` for CLI communication.
- **Hook server** -- Unix socket IPC for structured agent lifecycle events from Claude Code hooks.
- **CosmodromeHook binary** -- reads JSON from stdin, forwards to hook socket.
- **OSC 777 notifications** -- terminal notification support with attention ring animation.
- **Port detection** -- detects listening ports from child processes, shows click-to-open badges.
- **Session persistence** -- saves project/session state and scrollback to `~/Library/Application Support/Cosmodrome/`.
- **Command tracker** -- OSC 133 semantic prompt tracking for shell integration.
- **Modal keybindings** -- normal + command mode with `Ctrl+Space` toggle and vim-style navigation.
- **Command palette** -- `Cmd+P` for quick access to all actions.
- **Theme system** -- dark, light, and custom YAML themes.
- **Git worktree integration** -- multi-branch workflow support.

## [1.0.0] - 2026-03-08

### Added
- Initial release.
- **Metal renderer** -- single `MTKView` with viewport scissoring, shared glyph atlas, triple-buffered vertex data.
- **SwiftTerm backend** -- VT parsing via SwiftTerm with `TerminalBackend` protocol for future swap to libghostty-vt.
- **kqueue PTY multiplexer** -- single I/O thread for all PTY file descriptors.
- **Agent detection** -- inline pattern matching for Claude Code, Aider, Codex, and Gemini. States: working, needsInput, error, inactive.
- **Model detection** -- passive detection of which LLM model is in use.
- **Project and session management** -- `@Observable` models, YAML configuration, project store.
- **Layout engine** -- grid and focus modes.
- **Sidebar** -- SwiftUI project list with session thumbnails.
- **Status bar** -- agent state indicators, model display.
- **Completion actions** -- suggested next steps on task completion.
- **Configuration** -- YAML parsing for user and project config.
