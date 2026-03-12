# Contributing to Cosmodrome

Thank you for your interest in contributing to Cosmodrome. This document covers everything you need to get started.

Cosmodrome is a native macOS terminal emulator for developers who run multiple AI agents in parallel. It is built with Swift, AppKit, Metal, and SwiftTerm. It is not Electron, not Tauri, and not a wrapper around tmux.

## Getting Started

1. Fork the repository and clone your fork.
2. Make sure you have macOS 14 (Sonoma) or later.
3. Install Xcode or Command Line Tools (`xcode-select --install`).
4. Run `swift build` from the project root to verify the build succeeds.

## Development Setup

**Build targets:**

The project has 4 targets defined in `Package.swift`:

| Target | Type | Description |
|--------|------|-------------|
| `Core` | Library | Domain logic (no UI imports) |
| `CosmodromeApp` | Executable | Main app with AppKit + Metal UI |
| `CosmodromeHook` | Executable | Tiny binary for Claude Code hooks |
| `CosmodromeCLI` | Executable | CLI control tool (`cosmoctl`) |

**Build (debug):**

```bash
swift build
```

**Build (release):**

```bash
swift build -c release
```

**Build .app bundle:**

```bash
bash scripts/bundle.sh
```

**Build DMG:**

```bash
bash scripts/build-dmg.sh
```

**Run:**

```bash
.build/debug/CosmodromeApp
```

**Run tests:**

```bash
swift test
```

Note: running tests requires Xcode (not just Command Line Tools) because XCTest links against the Xcode toolchain.

**Prepare a release:**

```bash
bash scripts/release.sh 0.1.0
```

## Architecture

Read [ARCHITECTURE.md](ARCHITECTURE.md) for a full overview. The key points relevant to contributors:

- **2-thread model.** The main thread handles UI and Metal rendering. A single I/O thread handles all PTY file descriptors via kqueue. That is it -- two threads.
- **Single MTKView.** One Metal view renders all terminal sessions using viewport scissoring. There is not one view per session.
- **kqueue multiplexer.** All PTY I/O goes through a single kqueue-based multiplexer. No thread-per-PTY, no polling.
- **Agent detection is inline.** When PTY output arrives on the I/O thread, pattern matching runs immediately on that data. No separate polling thread.
- **Hook events are authoritative.** When Claude Code hooks are configured, structured JSON events supersede regex-based state detection.
- **@Observable for state.** Domain models use the Observation framework. No Combine, no NotificationCenter for domain events.

## Code Style

Follow the patterns already established in the codebase:

- `final class` by default. Only remove `final` when subclassing is intentional.
- `@Observable` for any model that drives UI.
- `private` access control by default. Use `internal` when needed by other files in the module. Use `public` only for the `Core` module API surface.
- No force-unwrapping outside tests. Use `guard let` or provide defaults.
- Prefer `throws` over `Result`. Prefer `async/await` over callbacks for async work.
- `struct` for value types, `class` only when identity or reference semantics matter.
- Files match the primary type they contain (`Project.swift` contains `class Project`).
- No abbreviations in type names (`TerminalRenderer`, not `TermRend`).

## Performance Rules

Performance is non-negotiable in this project. Every frame must be under 4ms. Every keystroke must reach the screen in under 5ms. If your change makes things slower, it will not be merged.

- **Profile before optimizing.** Use Instruments (Metal System Trace, Time Profiler, Allocations). Do not guess.
- **Dirty tracking everywhere.** Only re-render rows that changed. Only rebuild vertex data for dirty sessions.
- **Lazy everything.** Non-visible sessions get no rendering. Glyph atlas rasterizes on first use. Config parses on first access.
- **No allocation in the render loop.** The per-frame path must be allocation-free. Pre-allocate buffers and reuse them.
- **kqueue, not polling.** The I/O thread sleeps when there is no data. Zero CPU when idle.

## Dependencies

We keep dependencies to an absolute minimum. Currently the project depends on SwiftTerm and Yams. That is it.

Do not add a dependency for something achievable in under 100 lines of Swift. If you believe a new dependency is necessary, justify it clearly in your pull request description.

## Testing

- Write unit tests for all logic in `Sources/Core/`. Tests live in `Tests/CoreTests/`.
- Use `measure {}` blocks for performance-sensitive code paths.
- Test agent detection patterns, config parsing, layout calculations, and state transitions.
- Integration tests for PTY should spawn a real process and verify output flows through the backend.

## Pull Request Guidelines

- **One feature per PR.** Keep changes focused and reviewable.
- **Descriptive title.** Summarize what the PR does, not how.
- **Test new logic.** If you add or change behavior in `Core/`, add or update tests.
- **No breaking changes without discussion.** Open an issue first if your change affects the public API or architecture.
- **Profile performance-sensitive changes.** Include before/after numbers if your change touches the render path, I/O path, or any hot loop.

## Reporting Issues

Use the GitHub issue tracker. When filing a bug, include:

- macOS version
- Steps to reproduce
- Expected vs. actual behavior
- Any relevant terminal output or screenshots

Feature requests are welcome. Please check existing issues first to avoid duplicates.

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct v2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating, you are expected to uphold this code.

## License

By contributing, you agree that your contributions will be licensed under the MIT License. See [LICENSE](LICENSE) for the full text.
