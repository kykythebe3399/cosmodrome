import Foundation

/// Unix socket server for CLI control of the running Cosmodrome app.
/// Accepts JSON request-response pairs over individual connections.
public final class ControlServer {
    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.cosmodrome.control", qos: .userInitiated)
    private(set) public var socketPath: String?

    /// Handler for incoming commands. Called on the control queue.
    /// Must return a ControlResponse synchronously.
    public var onCommand: ((ControlRequest) -> ControlResponse)?

    public init() {}

    deinit {
        stop()
    }

    /// Start listening. Returns the socket path.
    @discardableResult
    public func start() -> String {
        let path = controlSocketPath()
        start(at: path)
        return path
    }

    /// Start listening on a specific path.
    public func start(at path: String) {
        stop()
        socketPath = path

        unlink(path)

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else {
            FileHandle.standardError.write("[ControlServer] socket() failed: \(errno)\n".data(using: .utf8)!)
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            FileHandle.standardError.write("[ControlServer] socket path too long\n".data(using: .utf8)!)
            close(listenFD); listenFD = -1
            return
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dst in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dst, src.baseAddress!, src.count)
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(listenFD, sockaddrPtr, addrLen)
            }
        }
        guard bindResult == 0 else {
            FileHandle.standardError.write("[ControlServer] bind() failed: \(errno)\n".data(using: .utf8)!)
            close(listenFD); listenFD = -1
            return
        }

        guard listen(listenFD, 5) == 0 else {
            FileHandle.standardError.write("[ControlServer] listen() failed: \(errno)\n".data(using: .utf8)!)
            close(listenFD); listenFD = -1
            return
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.listenFD, fd >= 0 {
                close(fd)
                self?.listenFD = -1
            }
        }
        source.resume()
        listenSource = source
    }

    /// Stop the server.
    public func stop() {
        listenSource?.cancel()
        listenSource = nil
        if listenFD >= 0 {
            close(listenFD); listenFD = -1
        }
        if let path = socketPath {
            unlink(path)
            socketPath = nil
        }
    }

    /// Standard socket path for this user.
    public static func defaultSocketPath() -> String {
        controlSocketPath()
    }

    private func acceptConnection() {
        let clientFD = accept(listenFD, nil, nil)
        guard clientFD >= 0 else { return }

        // Read request
        var data = Data()
        let bufSize = 8192
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }

        while true {
            let n = read(clientFD, buf, bufSize)
            if n > 0 {
                data.append(buf, count: n)
                // Check for newline delimiter (end of request)
                if data.last == 0x0A { break }
            } else {
                break
            }
        }

        let response: ControlResponse
        if let request = try? JSONDecoder().decode(ControlRequest.self, from: data) {
            response = onCommand?(request) ?? .failure("No handler registered")
        } else {
            response = .failure("Invalid JSON request")
        }

        // Send response
        if let responseData = try? JSONEncoder().encode(response) {
            var toSend = responseData
            toSend.append(0x0A) // newline delimiter
            toSend.withUnsafeBytes { buf in
                guard let ptr = buf.baseAddress else { return }
                _ = Darwin.write(clientFD, ptr, buf.count)
            }
        }

        close(clientFD)
    }
}

/// Standard control socket path.
private func controlSocketPath() -> String {
    let tmpDir = NSTemporaryDirectory()
    let uid = getuid()
    return "\(tmpDir)cosmodrome-\(uid).control.sock"
}
