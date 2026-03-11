import Core
import SwiftUI

/// Slide-out panel showing per-project activity timeline.
/// Toggled with Cmd+L.
struct ActivityLogView: View {
    let activityLog: ActivityLog
    let projectName: String
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Activity Log")
                    .font(Typo.subheadingMedium)
                    .foregroundColor(DS.textPrimary)

                Spacer()

                Text(projectName)
                    .font(Typo.body)
                    .foregroundColor(DS.textTertiary)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.textTertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(DS.bgElevated)

            Divider().opacity(0.2)

            // Event list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let events = activityLog.events.suffix(500)
                        ForEach(Array(events.enumerated()), id: \.offset) { idx, event in
                            ActivityEventRow(event: event)
                                .id(idx)
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                }
            }
        }
        .background(DS.bgPrimary)
    }
}

private struct ActivityEventRow: View {
    let event: ActivityEvent

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // Timestamp
            Text(relativeTimeString)
                .font(Typo.footnoteMono)
                .foregroundColor(DS.textTertiary)
                .frame(width: 44, alignment: .trailing)

            // Icon
            Image(systemName: iconName)
                .font(Typo.footnote)
                .foregroundColor(iconColor)
                .frame(width: 16)

            // Session name
            Text(event.sessionName)
                .font(Typo.footnoteMedium)
                .foregroundColor(DS.textSecondary)
                .frame(width: 70, alignment: .leading)
                .lineLimit(1)

            // Description
            Text(description)
                .font(Typo.body)
                .foregroundColor(DS.textPrimary.opacity(0.85))
                .lineLimit(2)

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(isHovered ? DS.bgHover : Color.clear)
                .animation(Anim.quick, value: isHovered)
        )
        .onHover { isHovered = $0 }
    }

    private var relativeTimeString: String {
        let elapsed = -event.timestamp.timeIntervalSinceNow
        if elapsed < 60 { return "\(Int(elapsed))s" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600))h" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: event.timestamp)
    }

    private var iconName: String {
        switch event.kind {
        case .taskStarted: return "play.fill"
        case .taskCompleted: return "checkmark.circle.fill"
        case .fileRead: return "doc"
        case .fileWrite: return "doc.fill"
        case .commandRun: return "terminal"
        case .error: return "exclamationmark.triangle.fill"
        case .modelChanged: return "cpu"
        case .stateChanged: return "arrow.right"
        case .subagentStarted: return "arrow.triangle.branch"
        case .subagentCompleted: return "checkmark.diamond"
        case .commandCompleted: return "terminal.fill"
        }
    }

    private var iconColor: Color {
        switch event.kind {
        case .taskStarted: return DS.stateWorking
        case .taskCompleted: return DS.stateWorking
        case .fileRead: return .blue
        case .fileWrite: return .orange
        case .commandRun: return .cyan
        case .error: return DS.stateError
        case .modelChanged: return .purple
        case .stateChanged: return DS.textTertiary
        case .subagentStarted: return .teal
        case .subagentCompleted: return .teal
        case .commandCompleted: return .mint
        }
    }

    private var description: String {
        switch event.kind {
        case .taskStarted:
            return "Started working"
        case .taskCompleted(let duration):
            return "Task completed (\(formatDuration(duration)))"
        case .fileRead(let path):
            return "Read \(path)"
        case .fileWrite(let path, let added, let removed):
            var s = "Write \(path)"
            if let a = added, let r = removed {
                s += " (+\(a) -\(r))"
            }
            return s
        case .commandRun(let command):
            return "Bash: \(command)"
        case .error(let message):
            return message
        case .modelChanged(let model):
            return "Model: \(model)"
        case .stateChanged(let from, let to):
            return "\(from.rawValue) → \(to.rawValue)"
        case .subagentStarted(let name, let description):
            return "Subagent: \(name) — \(description)"
        case .subagentCompleted(let name, let duration):
            return "Subagent done: \(name) (\(formatDuration(duration)))"
        case .commandCompleted(let command, let exitCode, let duration):
            let cmd = command ?? "command"
            let code = exitCode.map { " [exit \($0)]" } ?? ""
            return "\(cmd)\(code) (\(formatDuration(duration)))"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        }
        return "\(secs)s"
    }
}
