import Foundation

/// A notification emitted by a terminal session via OSC 777.
/// Format: ESC ] 777 ; notify ; title ; body ST
public struct TerminalNotification: Sendable {
    public let title: String
    public let body: String
    public let timestamp: Date

    public init(title: String, body: String, timestamp: Date = Date()) {
        self.title = title
        self.body = body
        self.timestamp = timestamp
    }
}
