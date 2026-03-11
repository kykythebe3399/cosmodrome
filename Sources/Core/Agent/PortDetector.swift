import Foundation

/// Detects TCP ports being listened on by a process and its children.
/// Uses `lsof` with machine-parseable output format.
public final class PortDetector {
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.cosmodrome.portdetector", qos: .utility)

    /// Called when detected ports change. (sessionId, [port])
    public var onPortsChanged: ((UUID, [UInt16]) -> Void)?

    /// Currently tracked sessions: sessionId → pid
    private var trackedSessions: [UUID: pid_t] = [:]
    private var knownPorts: [UUID: [UInt16]] = [:]

    public init() {}

    deinit {
        stop()
    }

    /// Start periodic port scanning.
    public func start(interval: TimeInterval = 3.0) {
        stop()
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + interval, repeating: interval)
        source.setEventHandler { [weak self] in
            self?.scan()
        }
        source.resume()
        timer = source
    }

    /// Stop scanning.
    public func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Register a session for port tracking.
    public func track(sessionId: UUID, pid: pid_t) {
        queue.async { [weak self] in
            self?.trackedSessions[sessionId] = pid
        }
    }

    /// Unregister a session.
    public func untrack(sessionId: UUID) {
        queue.async { [weak self] in
            self?.trackedSessions.removeValue(forKey: sessionId)
            self?.knownPorts.removeValue(forKey: sessionId)
        }
    }

    private func scan() {
        let sessions = trackedSessions
        guard !sessions.isEmpty else { return }

        // Get all listening TCP ports with their PIDs
        let portsByPid = detectListeningPorts()

        for (sessionId, pid) in sessions {
            // Collect ports for this PID and its children
            let childPids = getChildPids(of: pid)
            let allPids = Set([pid] + childPids)
            var ports: [UInt16] = []
            for p in allPids {
                if let pp = portsByPid[p] {
                    ports.append(contentsOf: pp)
                }
            }
            ports.sort()

            let old = knownPorts[sessionId] ?? []
            if ports != old {
                knownPorts[sessionId] = ports
                onPortsChanged?(sessionId, ports)
            }
        }
    }

    /// Run lsof to detect listening TCP ports.
    /// Returns: [pid: [port]]
    private func detectListeningPorts() -> [pid_t: [UInt16]] {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-iTCP", "-sTCP:LISTEN", "-P", "-n", "-F", "pn"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var result: [pid_t: [UInt16]] = [:]
        var currentPid: pid_t = 0

        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("p") {
                if let pid = pid_t(line.dropFirst()) {
                    currentPid = pid
                }
            } else if line.hasPrefix("n") && currentPid > 0 {
                // Format: "n*:PORT" or "n127.0.0.1:PORT" or "n[::1]:PORT"
                let addr = String(line.dropFirst())
                if let colonIdx = addr.lastIndex(of: ":") {
                    let portStr = addr[addr.index(after: colonIdx)...]
                    if let port = UInt16(portStr) {
                        result[currentPid, default: []].append(port)
                    }
                }
            }
        }

        return result
    }

    /// Get child PIDs of a process using pgrep.
    private func getChildPids(of parentPid: pid_t) -> [pid_t] {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", "\(parentPid)"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var pids: [pid_t] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let pid = pid_t(trimmed) {
                pids.append(pid)
                // Recurse one level deeper (e.g., shell → node → listener)
                pids.append(contentsOf: getChildPids(of: pid))
            }
        }
        return pids
    }
}
