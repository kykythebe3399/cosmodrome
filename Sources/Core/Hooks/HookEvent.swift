import Foundation

/// Represents an event received from the CosmodromeHook binary via Unix socket.
/// Claude Code invokes hooks at various lifecycle points; each invocation sends
/// a JSON payload that we parse into this struct.
///
/// Claude Code hook JSON structure (what we receive):
/// - hook_name: "PreToolUse" | "PostToolUse" | "Notification" | "Stop"
/// - session_id: optional UUID
/// - tool_name: "Agent" | "Bash" | "Read" | "Write" | "Edit" | "Glob" | "Grep" | etc.
/// - tool_input: string or JSON object with tool-specific fields
/// - tool_output: string or JSON object with result fields
/// - notification: human-readable message
/// - stop_reason: "end_turn" | "max_tokens" | "user_interrupt" | etc.
public struct HookEvent {
    public let hookName: String
    public let sessionId: UUID?
    public let timestamp: Date
    public let toolName: String?
    public let toolInput: String?
    public let toolOutput: String?
    public let notification: String?
    public let stopReason: String?

    // Structured fields parsed from tool_input/tool_output JSON
    public let filePath: String?
    public let command: String?
    public let exitCode: Int?
    public let agentDescription: String?
    public let costDelta: Double?

    public init(
        hookName: String,
        sessionId: UUID? = nil,
        timestamp: Date = Date(),
        toolName: String? = nil,
        toolInput: String? = nil,
        toolOutput: String? = nil,
        notification: String? = nil,
        stopReason: String? = nil,
        filePath: String? = nil,
        command: String? = nil,
        exitCode: Int? = nil,
        agentDescription: String? = nil,
        costDelta: Double? = nil
    ) {
        self.hookName = hookName
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolOutput = toolOutput
        self.notification = notification
        self.stopReason = stopReason
        self.filePath = filePath
        self.command = command
        self.exitCode = exitCode
        self.agentDescription = agentDescription
        self.costDelta = costDelta
    }

    /// Parse a HookEvent from JSON data received over the socket.
    /// Attempts to extract structured fields from tool_input and tool_output
    /// when they contain JSON objects.
    public static func parse(from data: Data) -> HookEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard let hookName = json["hook_name"] as? String else { return nil }

        let sessionId: UUID?
        if let idStr = json["session_id"] as? String {
            sessionId = UUID(uuidString: idStr)
        } else {
            sessionId = nil
        }

        let toolName = json["tool_name"] as? String
        let notification = json["notification"] as? String
        let stopReason = json["stop_reason"] as? String

        // tool_input can be a string or a JSON object
        var toolInputStr: String?
        var filePath: String?
        var command: String?
        var agentDescription: String?

        if let inputStr = json["tool_input"] as? String {
            toolInputStr = inputStr
            // Try to extract structured data from the string if it looks like JSON
            if let inputData = inputStr.data(using: .utf8),
               let inputJson = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any] {
                filePath = inputJson["file_path"] as? String ?? inputJson["path"] as? String
                command = inputJson["command"] as? String
                agentDescription = inputJson["description"] as? String ?? inputJson["prompt"] as? String
            }
        } else if let inputDict = json["tool_input"] as? [String: Any] {
            toolInputStr = (inputDict["command"] as? String)
                ?? (inputDict["file_path"] as? String)
                ?? (inputDict["description"] as? String)
            filePath = inputDict["file_path"] as? String ?? inputDict["path"] as? String
            command = inputDict["command"] as? String
            agentDescription = inputDict["description"] as? String ?? inputDict["prompt"] as? String
        }

        // tool_output: extract exit_code and cost info
        var toolOutputStr: String?
        var exitCode: Int?
        var costDelta: Double?

        if let outputStr = json["tool_output"] as? String {
            toolOutputStr = outputStr
        } else if let outputDict = json["tool_output"] as? [String: Any] {
            toolOutputStr = outputDict["stdout"] as? String ?? outputDict["output"] as? String
            exitCode = outputDict["exit_code"] as? Int ?? outputDict["exitCode"] as? Int
            costDelta = outputDict["cost"] as? Double
        }

        // Check for cost in notification messages (Claude Code sends cost updates)
        if hookName == "Notification", let msg = notification {
            costDelta = parseCostFromNotification(msg)
        }

        return HookEvent(
            hookName: hookName,
            sessionId: sessionId,
            timestamp: Date(),
            toolName: toolName,
            toolInput: toolInputStr,
            toolOutput: toolOutputStr,
            notification: notification,
            stopReason: stopReason,
            filePath: filePath,
            command: command,
            exitCode: exitCode,
            agentDescription: agentDescription,
            costDelta: costDelta
        )
    }

    /// Convert this hook event into an ActivityEvent.EventKind for the activity log.
    public func toEventKind() -> ActivityEvent.EventKind? {
        switch hookName {
        case "PreToolUse":
            guard let tool = toolName else { return nil }
            if tool == "Agent" {
                let desc = agentDescription ?? toolInput ?? ""
                return .subagentStarted(name: tool, description: desc)
            }
            if tool == "Bash" || tool == "Execute" {
                return .commandRun(command: command ?? toolInput ?? tool)
            }
            if tool == "Read" || tool == "Glob" || tool == "Grep" {
                return .fileRead(path: filePath ?? toolInput ?? "")
            }
            if tool == "Write" || tool == "Edit" {
                return .fileWrite(path: filePath ?? toolInput ?? "", added: nil, removed: nil)
            }
            return nil

        case "PostToolUse":
            guard let tool = toolName else { return nil }
            if tool == "Agent" {
                return .subagentCompleted(name: tool, duration: 0)
            }
            if tool == "Bash" || tool == "Execute" {
                if let exit = exitCode {
                    return .commandCompleted(
                        command: command ?? toolInput,
                        exitCode: exit,
                        duration: 0
                    )
                }
            }
            return nil

        case "Notification":
            if let msg = notification {
                return .error(message: msg)
            }
            return nil

        case "Stop":
            return .taskCompleted(duration: 0)

        default:
            return nil
        }
    }

    /// Attempt to parse a cost value from a notification message.
    /// Claude Code sometimes includes cost info like "Total cost: $1.23" or "Cost: $0.45".
    private static func parseCostFromNotification(_ message: String) -> Double? {
        // Match patterns like "$1.23", "cost: $0.45", "total: $2.00"
        let pattern = #"\$(\d+\.?\d*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        guard let match = regex.firstMatch(in: message, range: range),
              let costRange = Range(match.range(at: 1), in: message) else {
            return nil
        }
        return Double(message[costRange])
    }
}
