import AppKit
import Core
import Foundation

/// Manages the lifecycle of terminal sessions: spawning PTY processes,
/// connecting them to backends and the multiplexer, handling exits.
final class SessionManager {
    let multiplexer: PTYMultiplexer
    let projectStore: ProjectStore
    let portDetector = PortDetector()
    private var onSessionDirty: (() -> Void)?
    private var lastStatusParse: [UUID: Date] = [:]
    /// Called on main thread when the session list changes structurally (exit, restart).
    var onSessionListChanged: (() -> Void)?
    private var recorders: [UUID: AsciicastRecorder] = [:]

    /// Socket path for the hook server — injected into spawned sessions' environment.
    var hookSocketPath: String?

    /// Called on main thread when an agent completes a task (working → not working).
    /// Parameters: session, filesChanged, taskDuration
    var onTaskCompleted: ((Session, [String], TimeInterval) -> Void)?

    /// Called on main thread when a terminal notification (OSC 777) is received.
    var onTerminalNotification: ((Session, TerminalNotification) -> Void)?

    init(projectStore: ProjectStore) {
        self.projectStore = projectStore
        self.multiplexer = PTYMultiplexer()
        setupPortDetector()
    }

    private func setupPortDetector() {
        portDetector.onPortsChanged = { [weak self] sessionId, ports in
            DispatchQueue.main.async {
                guard let self else { return }
                for project in self.projectStore.projects {
                    if let session = project.sessions.first(where: { $0.id == sessionId }) {
                        session.detectedPorts = ports
                        break
                    }
                }
            }
        }
        portDetector.start()
    }

    /// Set callback for when any session has new output (triggers redraw).
    func setDirtyHandler(_ handler: @escaping () -> Void) {
        self.onSessionDirty = handler
    }

    /// Start a session: spawn PTY, create backend, register with multiplexer.
    func startSession(_ session: Session) throws {
        guard !session.isRunning else { return }

        let cols: UInt16 = 80
        let rows: UInt16 = 24
        let cwd = session.cwd == "." ? FileManager.default.currentDirectoryPath : session.cwd

        // Inject hook server env vars so CosmodromeHook can reach us
        var env = session.environment
        if let socketPath = hookSocketPath {
            env["COSMODROME_HOOK_SOCKET"] = socketPath
        }
        env["COSMODROME_SESSION_ID"] = session.id.uuidString

        let result = try spawnPTY(
            command: session.command,
            arguments: session.arguments,
            environment: env,
            cwd: cwd,
            size: (cols: cols, rows: rows)
        )

        let backend = SwiftTermBackend(cols: Int(cols), rows: Int(rows))

        // Wire up command completion tracking (OSC 133)
        let sid = session.id
        let sname = session.name
        backend.commandTracker?.onCommandCompleted = { [weak self] command, exitCode, duration in
            guard let self else { return }
            DispatchQueue.main.async {
                if let project = self.findProject(for: session) {
                    project.activityLog.append(ActivityEvent(
                        timestamp: Date(),
                        sessionId: sid,
                        sessionName: sname,
                        kind: .commandCompleted(command: command, exitCode: exitCode, duration: duration)
                    ))
                }
            }
        }

        // Wire up OSC 777 notification handler
        backend.onNotification = { [weak self] notification in
            DispatchQueue.main.async {
                session.hasUnreadNotification = true
                session.lastNotification = notification
                self?.onTerminalNotification?(session, notification)
            }
        }

        let detector: AgentDetector? = session.isAgent
            ? AgentDetector(
                agentType: session.agentType ?? "claude",
                sessionId: session.id,
                sessionName: session.name
            )
            : nil

        session.backend = backend
        session.ptyFD = result.fd
        session.pid = result.pid
        session.isRunning = true
        session.exitedUnexpectedly = false
        session.taskStartedAt = nil
        session.filesChangedInTask = []

        let onDirty = onSessionDirty ?? {}
        let sessionId = session.id

        let io = PTYMultiplexer.SessionIO(
            id: sessionId,
            backend: backend,
            agentDetector: detector,
            onOutput: { [weak self] in
                if let detector {
                    let newState = detector.state
                    let oldState = session.agentState
                    let model = detector.modelDetector.currentModel
                    let events = detector.consumeEvents()

                    DispatchQueue.main.async {
                        session.agentState = newState
                        if model != session.agentModel { session.agentModel = model }

                        // Parse Claude Code status bar (throttled)
                        self?.updateStatusLine(session: session, backend: backend)

                        // Append events to project's activity log
                        if let project = self?.findProject(for: session) {
                            project.activityLog.append(contentsOf: events)
                        }

                        // Track files changed during task
                        for event in events {
                            if case .fileWrite(let path, _, _) = event.kind {
                                if session.agentState == .working {
                                    session.filesChangedInTask.append(path)
                                }
                            }
                        }

                        // Handle state transitions
                        if newState != oldState {
                            // Starting a new task
                            if newState == .working && oldState != .working {
                                session.taskStartedAt = Date()
                                session.filesChangedInTask = []
                            }

                            // Task completed (was working, now not)
                            if oldState == .working && newState != .working {
                                let duration = session.taskStartedAt
                                    .map { Date().timeIntervalSince($0) } ?? 0
                                let files = session.filesChangedInTask

                                // Log completion event
                                if let project = self?.findProject(for: session) {
                                    project.activityLog.append(ActivityEvent(
                                        timestamp: Date(),
                                        sessionId: session.id,
                                        sessionName: session.name,
                                        kind: .taskCompleted(duration: duration)
                                    ))
                                }

                                // Trigger completion actions
                                self?.onTaskCompleted?(session, files, duration)
                            }

                            // Notification on state change to needsInput/error
                            if let project = self?.findProject(for: session) {
                                AgentNotifications.notifyAgentState(project: project, session: session)
                            }
                        }
                    }
                }
                DispatchQueue.main.async {
                    onDirty()
                }
            },
            onExit: { [weak self] in
                self?.handleSessionExit(session)
            },
            onRawOutput: { [weak self] bytes in
                self?.recorders[sessionId]?.recordOutput(bytes)
            }
        )

        multiplexer.register(fd: result.fd, session: io)
        portDetector.track(sessionId: session.id, pid: result.pid)

        // Log session start
        if let project = findProject(for: session) {
            project.activityLog.append(ActivityEvent(
                timestamp: Date(),
                sessionId: session.id,
                sessionName: session.name,
                kind: .taskStarted
            ))
        }

        // Inject minimal shell integration for OSC 133 (command tracking)
        injectShellIntegration(session: session, fd: result.fd)
    }

    /// Send a tiny shell snippet that enables OSC 133 semantic prompts.
    /// This lets CommandTracker log shell commands in the activity log.
    private func injectShellIntegration(session: Session, fd: Int32) {
        // Only inject for interactive shells
        let shell = (session.command as NSString).lastPathComponent
        guard ["zsh", "bash", "fish"].contains(shell) else { return }

        let snippet: String
        switch shell {
        case "zsh":
            // precmd: emit D;exitcode then A (prompt start)
            // preexec: emit B (command start)
            snippet = [
                "__cosmo_precmd() { local ec=$?; printf '\\e]133;D;%d\\a\\e]133;A\\a' \"$ec\"; }",
                "__cosmo_preexec() { printf '\\e]133;B\\a'; }",
                "precmd_functions+=(__cosmo_precmd)",
                "preexec_functions+=(__cosmo_preexec)",
                "clear",
                "",
            ].joined(separator: "\n")
        case "bash":
            snippet = [
                "__cosmo_prompt() { local ec=$?; printf '\\e]133;D;%d\\a\\e]133;A\\a' \"$ec\"; }",
                "trap 'printf \"\\e]133;B\\a\"' DEBUG",
                "PROMPT_COMMAND=\"__cosmo_prompt${PROMPT_COMMAND:+;$PROMPT_COMMAND}\"",
                "clear",
                "",
            ].joined(separator: "\n")
        case "fish":
            snippet = [
                "function __cosmo_prompt --on-event fish_prompt; printf '\\e]133;A\\a'; end",
                "function __cosmo_preexec --on-event fish_preexec; printf '\\e]133;B\\a'; end",
                "function __cosmo_postexec --on-event fish_postexec; printf '\\e]133;D;%d\\a' $status; end",
                "clear",
                "",
            ].joined(separator: "\n")
        default:
            return
        }

        if let data = snippet.data(using: .utf8) {
            // Small delay so the shell has time to initialize
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.multiplexer.send(to: fd, data: data)
            }
        }
    }

    /// Stop a session: kill the process, clean up.
    func stopSession(_ session: Session) {
        guard session.isRunning else { return }

        portDetector.untrack(sessionId: session.id)

        if session.pid > 0 {
            kill(session.pid, SIGTERM)
        }
        if session.ptyFD >= 0 {
            multiplexer.unregister(fd: session.ptyFD)
        }

        session.isRunning = false
        session.ptyFD = -1
        session.pid = 0
        session.backend = nil
        session.agentState = .inactive
        session.agentModel = nil
        session.agentContext = nil
        session.agentMode = nil
        session.agentCost = nil
        session.taskStartedAt = nil
        session.filesChangedInTask = []
        session.detectedPorts = []
        lastStatusParse.removeValue(forKey: session.id)
    }

    /// Start all auto-start sessions in a project.
    func startAutoStartSessions(for project: Project) {
        for session in project.sessions where session.autoStart {
            do {
                try startSession(session)
            } catch {
                FileHandle.standardError.write("[Cosmodrome] Failed to start session '\(session.name)': \(error)\n".data(using: .utf8)!)
            }
        }
    }

    /// Write data to a session's PTY.
    func write(to session: Session, data: Data) {
        guard session.ptyFD >= 0 else { return }
        multiplexer.send(to: session.ptyFD, data: data)
    }

    // MARK: - Recording

    /// Start recording a session's output in asciicast v2 format.
    func startRecording(session: Session) {
        guard recorders[session.id] == nil else { return }

        let backend = session.backend
        let width = backend?.cols ?? 80
        let height = backend?.rows ?? 24

        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
            ?? NSTemporaryDirectory()
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let path = "\(dir)/cosmodrome-\(session.name)-\(timestamp).cast"

        do {
            let recorder = try AsciicastRecorder(
                path: path, width: width, height: height, title: session.name
            )
            recorders[session.id] = recorder
        } catch {
            FileHandle.standardError.write("[Cosmodrome] Failed to start recording: \(error)\n".data(using: .utf8)!)
        }
    }

    /// Stop recording a session.
    func stopRecording(session: Session) {
        guard let recorder = recorders.removeValue(forKey: session.id) else { return }
        recorder.close()
    }

    /// Check if a session is being recorded.
    func isRecording(session: Session) -> Bool {
        recorders[session.id] != nil
    }

    // MARK: - Status Line Parsing

    /// Parse Claude Code's status bar from the terminal buffer (throttled to every 3s).
    private func updateStatusLine(session: Session, backend: TerminalBackend) {
        let now = Date()
        if let last = lastStatusParse[session.id], now.timeIntervalSince(last) < 3.0 {
            return
        }
        lastStatusParse[session.id] = now

        let info = Self.parseStatusLine(from: backend)
        if info.context != session.agentContext { session.agentContext = info.context }
        if info.mode != session.agentMode { session.agentMode = info.mode }
        if info.cost != session.agentCost { session.agentCost = info.cost }
    }

    /// Read the bottom rows of the terminal buffer and extract status bar info.
    private static func parseStatusLine(from backend: TerminalBackend) -> (context: String?, mode: String?, cost: String?) {
        backend.lock()
        let rows = backend.rows
        let cols = backend.cols

        // Read bottom 2 rows (Claude Code status bar sits at the bottom)
        var text = ""
        for row in max(0, rows - 2)..<rows {
            for col in 0..<cols {
                let cell = backend.cell(row: row, col: col)
                let cp = cell.codepoint
                if cp >= 32 && cp < 0x10000 {
                    text.append(Character(Unicode.Scalar(cp)!))
                } else {
                    text.append(" ")
                }
            }
            text.append(" ")
        }
        backend.unlock()

        var context: String?
        var mode: String?
        var cost: String?

        // Context: "45k/200k" or "45.2k / 200k" or "128.5k/200k"
        if let range = text.range(of: #"\d+\.?\d*[kK]\s*/\s*\d+\.?\d*[kK]"#, options: .regularExpression) {
            context = String(text[range]).replacingOccurrences(of: " ", with: "")
        }

        // Cost: "$0.23" or "$12.45"
        if let range = text.range(of: #"\$\d+\.\d+"#, options: .regularExpression) {
            cost = String(text[range])
        }

        // Mode: match known Claude Code permission modes
        // Check more specific patterns first to avoid false positives
        let modePatterns: [(pattern: String, label: String)] = [
            (#"\bbypass\w*"#, "Bypass"),
            (#"\bdangerously\b"#, "Bypass"),
            (#"\bplan\b"#, "Plan"),
            (#"\bauto\b"#, "Auto"),
            (#"\bdefault\b"#, "Default"),
        ]
        for (pattern, label) in modePatterns {
            if text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                mode = label
                break
            }
        }

        return (context, mode, cost)
    }

    // MARK: - Private

    func findProject(for session: Session) -> Project? {
        projectStore.projects.first { $0.sessions.contains { $0.id == session.id } }
    }

    private func handleSessionExit(_ session: Session) {
        let wasRunning = session.isRunning
        session.isRunning = false
        session.agentState = .inactive

        // Log session exit
        if let project = findProject(for: session) {
            project.activityLog.append(ActivityEvent(
                timestamp: Date(),
                sessionId: session.id,
                sessionName: session.name,
                kind: .taskCompleted(duration: 0)
            ))
        }

        // Stop recording if active
        if let recorder = recorders.removeValue(forKey: session.id) {
            recorder.close()
        }

        // Mark unexpected exit (process died while it was running)
        if wasRunning {
            session.exitedUnexpectedly = true
        }

        if session.autoRestart {
            session.restartAttempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + session.restartDelay) { [weak self] in
                try? self?.startSession(session)
            }
        }

        // Rebuild session list so UI reflects the exit
        DispatchQueue.main.async { [weak self] in
            self?.onSessionListChanged?()
        }
    }
}
