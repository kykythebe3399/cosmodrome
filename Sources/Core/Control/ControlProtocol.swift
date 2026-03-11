import Foundation

/// JSON request-response protocol for the control socket.
/// Clients send a JSON request, server responds with a JSON response.
public struct ControlRequest: Codable {
    public let command: String
    public let args: [String: String]?

    public init(command: String, args: [String: String]? = nil) {
        self.command = command
        self.args = args
    }
}

public struct ControlResponse: Codable {
    public let ok: Bool
    public let data: String?
    public let error: String?

    public init(ok: Bool, data: String? = nil, error: String? = nil) {
        self.ok = ok
        self.data = data
        self.error = error
    }

    public static func success(_ data: String) -> ControlResponse {
        ControlResponse(ok: true, data: data)
    }

    public static func failure(_ error: String) -> ControlResponse {
        ControlResponse(ok: false, error: error)
    }
}
