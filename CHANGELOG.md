# Changelog

All notable changes to Cosmodrome are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.3.0] - 2026-03-15

### Added

#### Intelligence Layer
- **Event persistence** -- SQLite-backed storage (`EventStore`, `SQLiteStore`, `EventPersister`) at `~/Library/Application Support/Cosmodrome/cosmodrome.db`. Persists all agent activity, session history, tasks, cost data, error patterns, and workflow sequences. Async batch flushing to avoid blocking I/O.
- **Cost prediction** -- `CostPredictor` estimates task cost (median + p75) based on historical similar tasks, keyed by classification and file count. Zero LLM, purely statistical.
- **Efficiency tracking** -- `EfficiencyTracker` compares agent performance across task types (refactor, feature, bugfix, test, docs). Shows which agent is best for which task type.
- **Task classification** -- `TaskClassifier` heuristically classifies tasks into 6 types based on event patterns (files changed, test presence, errors, commands).
- **Workflow mining** -- `WorkflowMiner` detects workflow bigrams from historical sequences and suggests next actions with probability scores (e.g., "after editing auth/, you run tests 85% of the time").
- **Pattern learning** -- `PatternLearner` learns which error patterns historically lead to stuck loops. Predicts stuck probability for new errors.
- **Urgency scoring** -- `UrgencyScorer` scores sessions 0-100 based on state, stuck info, and time in state. Returns urgency level + reason for UI prioritization.

#### CosmodromeDaemon
- **Headless daemon** -- `CosmodromeDaemon` runs without UI, ingests Claude Code hook events, persists to EventStore, and serves intelligence queries over Unix sockets. Two socket interfaces: hook socket for event ingestion, control socket for CLI queries (`status`, `query-history`, `query-patterns`, `query-cost`, `query-efficiency`, `query-workflows`). Automatic cleanup of old data.

#### UI/UX Overhaul
- **Design system** -- `DesignSystem.swift` centralizes spacing, border radii, typography scale, semantic colors, animation speeds, and reusable modifiers. `ThemeState` (@Observable singleton) resolves theme colors with derived surfaces.
- **Session thumbnails redesigned** -- Left border accent strip (3px, state color) as primary indicator. Unread dot for non-focused sessions. Notification badge. Cleaner content hierarchy with session index.
- **Activity log smart filtering** -- Default "Smart" filter excludes noise (state transitions), focuses on meaningful events. "While You Were Away" banner shows summary after 5min+ absence. Time filters (Last Hour / Today / All) and event filters (Smart / Files / Commands / Errors / All).
- **Status bar fleet summary** -- Distinct shapes + colors for accessibility: filled circle (working), half-circle (needs input), triangle (error). Total session count + fleet cost.
- **Sidebar restructured** -- Collapsible project sections, cleaner spacing, session context menu (Focus, Restart, Close).
- **Terminal content improvements** -- Grid gap (4px), cell corner radius (6px), session header overlay (24px), session border/label CALayers. Focus tracking with hover states + session dimming.
- **Command palette themes** -- Individual theme entries (Dark, Light, custom) with active indicator. Themes category in palette. Overlay z-position fix for visibility above session headers.

#### Themes
- **Custom theme support** -- YAML-based custom themes loaded from `Resources/Themes/` and `~/.config/cosmodrome/themes/`. Luminance-based dark/light detection.
- **Daobeam theme** -- New bundled light theme (beige background, dark foreground).

### Fixed
- **Git branch visibility** -- Correctly detected and displayed in sidebar.
- **Phantom scroll after focus change** -- 150ms scroll suppression guard after session focus change prevents erratic jumping (same root cause as Ghostty #11276).
- **Smooth scrolling** -- Sub-line precision with accumulator carrying remainder between events.
- **Notification sound removed** -- Was causing UX friction; notifications are now silent.
- **Context menu labels** -- Renamed for clarity.

## [0.2.0] - 2026-03-14

### Added
- **Session Narrative** -- heuristic-based narrative engine (`SessionNarrative`) replaces raw state labels with contextual descriptions. "Working" becomes "Editing auth module -- 8 files, 2m". "Error" becomes "Error: compile error in auth.ts". Zero LLM, zero latency, works offline.
- **Stuck Detection** -- `StuckDetector` identifies error-retry loops (3+ cycles within 10 min). Session cards show "stuck" badge with retry count and duration instead of misleading "working" state.
- **Event Grouping** -- `ActivityLog.groupEvents()` collapses related events into logical units: task blocks (taskStarted...taskCompleted), file clusters (3+ writes within 60s), state flicker (3+ rapid transitions).
- **Buffer State Scanner** -- `BufferStateScanner` reads rendered terminal buffer cells for Claude Code TUI state detection. Immune to ANSI stripping issues. Confidence-based (high/medium/none).
- **Consolidated Buffer Scanning** -- `runBufferScans()` reads the terminal buffer once per output event and runs all scans (status line, agent state, prompt detection, agent exit) against the shared snapshot. Eliminates 4 separate lock acquisitions per scan cycle.
- **Richer Completion Actions** -- `CompletionActions` now accepts full `CompletionContext` (stats, events, narrative, stuck info). Summary line shows "Editing auth module. 15 files, tests passing, 5m, $4.20." instead of bare "Task completed (5m)". Test-aware suggestions: "Re-run tests (were failing)".
- **Task completion notifications** -- macOS notification + attention badge fires when an agent transitions working -> inactive (task done), not just on needsInput/error.
- **`agentSince` timeout** -- "Collecting status..." placeholder disappears after 10s even if status line parsing fails, showing minimal agent info instead.
- **`readRowsAtBottom()` API** -- `TerminalBackend` protocol gains bulk row reading. Single yDisp snap/restore instead of per-cell mutations, preventing scroll jitter.

### Fixed
- **Mode badge always visible** -- permission mode badge (Plan/Accept Edits/Bypass/Auto) now shown for all non-Default modes. Previously hidden for "Accept Edits".
- **Case-insensitive ctx detection** -- all `ctx:` regex patterns now use `(?i)` flag. Prevents silent detection failure if Claude Code changes casing.
- **Git branch CWD resolution** -- sessions with `cwd: "."` now resolve to absolute path at spawn time. Previously all default sessions showed the app's CWD branch.
- **Thread safety in AgentDetector** -- added NSLock protecting shared mutable state (`_pendingEvents`, `_state`, `hasHookData`, `lastHookEvent`, `previousState`) between I/O thread and main thread.
- **BufferStateScanner spinner false positive** -- spinner pattern now requires line-start position, preventing status bar characters from being misdetected as working state.
- **User font config loaded at startup** -- font family, size, and line height from `~/.config/cosmodrome/config.yml` are now properly applied (contributor: @thisloke).
- **Cmd+Q app termination** -- Cmd+Q now passes through to AppKit menu system instead of being captured by keybinding handler (contributor: @cwmahan).
- **Font size config precedence** -- explicit user config font size takes priority over saved state. Saved state only restores when config doesn't specify a size (contributor: @cwmahan).

### Removed
- **`send_input` MCP tool** -- removed to align with "observe, never orchestrate" philosophy. Cosmodrome no longer writes to agent PTYs.
- **`cosmoctl send` CLI command** -- removed for the same reason.
- **`cosmoctl new-session` CLI command** -- removed; session creation is a UI-only operation.
- **Git worktree integration** -- removed `GitWorktree` and all worktree management from the command palette. Worktree management is outside Cosmodrome's scope.
- **`Prototypes/GhosttyAppleScript/`** -- removed external terminal orchestration prototype.

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
