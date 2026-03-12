import Core
import SwiftUI

// MARK: - Filter Types

enum TimeFilter: CaseIterable {
    case lastHour, today, all

    var label: String {
        switch self {
        case .lastHour: return "Last Hour"
        case .today: return "Today"
        case .all: return "All"
        }
    }

    var cutoff: Date {
        switch self {
        case .lastHour: return Date().addingTimeInterval(-3600)
        case .today: return Calendar.current.startOfDay(for: Date())
        case .all: return .distantPast
        }
    }
}

enum EventFilter: CaseIterable {
    case all, files, commands, errors

    var label: String {
        switch self {
        case .all: return "All"
        case .files: return "Files"
        case .commands: return "Commands"
        case .errors: return "Errors"
        }
    }

    func matches(_ kind: ActivityEvent.EventKind) -> Bool {
        switch self {
        case .all: return true
        case .files: return kind.category == .files
        case .commands: return kind.category == .commands
        case .errors: return kind.category == .errors
        }
    }
}

// MARK: - Main View

/// Full-screen activity log overlay. The hero feature of Cosmodrome.
/// Shows what all agents did, grouped by session, with filtering and summary.
struct ActivityLogView: View {
    let projects: [Project]
    var onFocusSession: (UUID, UUID) -> Void  // (projectId, sessionId)
    var onDismiss: () -> Void

    @State private var timeFilter: TimeFilter = .lastHour
    @State private var eventFilter: EventFilter = .all
    @State private var expandedSessions: Set<UUID> = []
    @State private var initialExpandDone = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            summaryBar
            Divider().opacity(0.3)
            filterBar
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
            Divider().opacity(0.3)

            if sessionEntries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(sessionEntries, id: \.sessionId) { entry in
                            SessionSection(
                                entry: entry,
                                eventFilter: eventFilter,
                                isExpanded: expandedSessions.contains(entry.sessionId),
                                onToggle: { toggleSession(entry.sessionId) },
                                onFocus: {
                                    if let pid = entry.projectId {
                                        onFocusSession(pid, entry.sessionId)
                                    }
                                }
                            )
                        }
                    }
                    .padding(Spacing.lg)
                }
            }
        }
        .background(DS.bgPrimary)
        .onAppear {
            if !initialExpandDone {
                // Auto-expand sessions that have recent activity
                expandedSessions = Set(sessionEntries.prefix(5).map(\.sessionId))
                initialExpandDone = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.lg) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 14))
                    .foregroundColor(DS.accent)
                Text("Activity Log")
                    .font(Typo.title)
                    .foregroundColor(DS.textPrimary)
            }

            Spacer()

            // Time filter
            ForEach(TimeFilter.allCases, id: \.self) { tf in
                timeFilterButton(tf)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(DS.bgHover)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(DS.bgSidebar)
    }

    private func timeFilterButton(_ tf: TimeFilter) -> some View {
        let isActive = timeFilter == tf
        return Button(action: { withAnimation(Anim.quick) { timeFilter = tf } }) {
            Text(tf.label)
                .font(Typo.bodyMedium)
                .foregroundColor(isActive ? DS.textPrimary : DS.textTertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(isActive ? DS.bgSelected : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        let summary = aggregateSummary
        return HStack(spacing: Spacing.lg) {
            summaryStat(
                icon: "checkmark.circle.fill",
                value: "\(summary.tasksCompleted)",
                label: "tasks completed",
                color: DS.stateWorking
            )
            summaryStat(
                icon: "doc.fill",
                value: "\(summary.filesChanged)",
                label: "files changed",
                color: .orange
            )
            summaryStat(
                icon: "exclamationmark.triangle.fill",
                value: "\(summary.errors)",
                label: summary.errors == 1 ? "error" : "errors",
                color: summary.errors > 0 ? DS.stateError : DS.textTertiary
            )
            summaryStat(
                icon: "person.2.fill",
                value: "\(summary.activeSessions)",
                label: "sessions",
                color: DS.accent
            )

            // Total cost across all projects
            let totalCost = projects.reduce(0.0) { $0 + $1.totalCost }
            if totalCost > 0 {
                summaryStat(
                    icon: "dollarsign.circle.fill",
                    value: SessionStats.formatCost(totalCost),
                    label: "total cost",
                    color: DS.textSecondary
                )
            }

            Spacer()

            Text("\(allFilteredEvents.count) events")
                .font(Typo.footnoteMono)
                .foregroundColor(DS.textTertiary)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(DS.bgElevated)
    }

    private func summaryStat(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color)
            Text(value)
                .font(Typo.subheadingMedium)
                .foregroundColor(DS.textPrimary)
            Text(label)
                .font(Typo.body)
                .foregroundColor(DS.textTertiary)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(EventFilter.allCases, id: \.self) { ef in
                eventFilterButton(ef)
            }
            Spacer()

            // Expand/collapse all
            Button(action: {
                if expandedSessions.count == sessionEntries.count {
                    expandedSessions.removeAll()
                } else {
                    expandedSessions = Set(sessionEntries.map(\.sessionId))
                }
            }) {
                HStack(spacing: 2) {
                    Image(systemName: expandedSessions.count == sessionEntries.count ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                        .font(.system(size: 9))
                    Text(expandedSessions.count == sessionEntries.count ? "Collapse All" : "Expand All")
                        .font(Typo.body)
                }
                .foregroundColor(DS.textSecondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .hoverHighlight()
            }
            .buttonStyle(.plain)
        }
    }

    private func eventFilterButton(_ ef: EventFilter) -> some View {
        let isActive = eventFilter == ef
        let count = countFor(filter: ef)
        return Button(action: { withAnimation(Anim.quick) { eventFilter = ef } }) {
            HStack(spacing: Spacing.xs) {
                Text(ef.label)
                    .font(Typo.bodyMedium)
                if count > 0 {
                    Text("\(count)")
                        .font(Typo.caption)
                        .foregroundColor(isActive ? DS.textPrimary : DS.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(DS.bgHover))
                }
            }
            .foregroundColor(isActive ? DS.textPrimary : DS.textSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(isActive ? DS.bgSelected : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.system(size: 40))
                .foregroundColor(DS.textTertiary)
            Text("No activity yet")
                .font(Typo.subheading)
                .foregroundColor(DS.textSecondary)
            Text("Agent events will appear here as they work")
                .font(Typo.body)
                .foregroundColor(DS.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data

    private var allFilteredEvents: [ActivityEvent] {
        let cutoff = timeFilter.cutoff
        return projects.flatMap { project in
            project.activityLog.events.filter { event in
                event.timestamp > cutoff && eventFilter.matches(event.kind)
            }
        }
    }

    private var aggregateSummary: ActivitySummary {
        let cutoff = timeFilter.cutoff
        var tasks = 0, errors = 0, sessions = Set<UUID>()
        var files = Set<String>()

        for project in projects {
            let s = project.activityLog.summary(since: cutoff)
            tasks += s.tasksCompleted
            errors += s.errors
            files.formUnion(
                project.activityLog.events
                    .filter { $0.timestamp > cutoff }
                    .compactMap { if case .fileWrite(let p, _, _) = $0.kind { return p } else { return nil } }
            )
            sessions.formUnion(
                project.activityLog.events
                    .filter { $0.timestamp > cutoff }
                    .map(\.sessionId)
            )
        }

        return ActivitySummary(
            tasksCompleted: tasks,
            filesChanged: files.count,
            errors: errors,
            activeSessions: sessions.count,
            eventCount: allFilteredEvents.count
        )
    }

    /// Session entries sorted by most recent activity.
    private var sessionEntries: [SessionEntry] {
        let cutoff = timeFilter.cutoff

        var entries: [UUID: SessionEntry] = [:]

        for project in projects {
            let events = project.activityLog.events.filter { $0.timestamp > cutoff }
            let grouped = Dictionary(grouping: events, by: \.sessionId)

            for (sessionId, sessionEvents) in grouped {
                let filtered = sessionEvents.filter { eventFilter.matches($0.kind) }
                guard !filtered.isEmpty else { continue }

                let session = project.sessions.first(where: { $0.id == sessionId })
                let fileCount = Set(sessionEvents.compactMap {
                    if case .fileWrite(let p, _, _) = $0.kind { return p } else { return nil }
                }).count
                let cost = session?.stats.totalCost ?? 0
                let lastActivity = filtered.map(\.timestamp).max() ?? .distantPast

                entries[sessionId] = SessionEntry(
                    sessionId: sessionId,
                    projectId: project.id,
                    sessionName: session?.name ?? sessionEvents.first?.sessionName ?? "Unknown",
                    projectName: project.name,
                    agentState: session?.agentState ?? .inactive,
                    agentType: session?.agentType,
                    model: session?.agentModel,
                    cost: cost,
                    fileCount: fileCount,
                    lastActivity: lastActivity,
                    events: filtered.sorted(by: { $0.timestamp > $1.timestamp })
                )
            }
        }

        return entries.values.sorted { $0.lastActivity > $1.lastActivity }
    }

    private func countFor(filter: EventFilter) -> Int {
        let cutoff = timeFilter.cutoff
        return projects.reduce(0) { total, project in
            total + project.activityLog.events.count(where: { $0.timestamp > cutoff && filter.matches($0.kind) })
        }
    }

    private func toggleSession(_ id: UUID) {
        if expandedSessions.contains(id) {
            expandedSessions.remove(id)
        } else {
            expandedSessions.insert(id)
        }
    }
}

// MARK: - Session Entry Model

private struct SessionEntry {
    let sessionId: UUID
    let projectId: UUID?
    let sessionName: String
    let projectName: String
    let agentState: AgentState
    let agentType: String?
    let model: String?
    let cost: Double
    let fileCount: Int
    let lastActivity: Date
    let events: [ActivityEvent]
}

// MARK: - Session Section

private struct SessionSection: View {
    let entry: SessionEntry
    let eventFilter: EventFilter
    let isExpanded: Bool
    var onToggle: () -> Void
    var onFocus: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Session header row
            Button(action: onToggle) {
                HStack(spacing: Spacing.sm) {
                    // Expand chevron
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DS.textTertiary)
                        .frame(width: 12)

                    // State dot
                    Circle()
                        .fill(DS.stateColor(for: entry.agentState))
                        .frame(width: 7, height: 7)

                    // Session name
                    Text(entry.sessionName)
                        .font(Typo.subheadingMedium)
                        .foregroundColor(DS.textPrimary)
                        .lineLimit(1)

                    // State label
                    Text(stateLabel)
                        .font(Typo.footnote)
                        .foregroundColor(DS.stateColor(for: entry.agentState).opacity(0.8))

                    // Agent type + model
                    if let type = entry.agentType {
                        Text(type.capitalized)
                            .font(Typo.footnote)
                            .foregroundColor(DS.textTertiary)
                    }
                    if let model = entry.model {
                        Text(model)
                            .font(Typo.captionMono)
                            .foregroundColor(DS.textTertiary)
                    }

                    Spacer()

                    // Stats
                    if entry.cost > 0 {
                        Text(SessionStats.formatCost(entry.cost))
                            .font(Typo.footnoteMono)
                            .foregroundColor(DS.textSecondary)
                    }

                    if entry.fileCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 8))
                            Text("\(entry.fileCount)")
                                .font(Typo.captionMono)
                        }
                        .foregroundColor(.orange.opacity(0.7))
                    }

                    Text("\(entry.events.count) events")
                        .font(Typo.captionMono)
                        .foregroundColor(DS.textTertiary)

                    // Project badge
                    Text(entry.projectName)
                        .font(Typo.caption)
                        .foregroundColor(DS.textTertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(DS.bgHover)
                        .cornerRadius(Radius.sm)

                    // Focus button (visible on hover)
                    if isHovered {
                        Button(action: onFocus) {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 10))
                                .foregroundColor(DS.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            // Event rows (when expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entry.events.prefix(100).enumerated()), id: \.offset) { _, event in
                        ActivityEventRow(event: event)
                    }

                    if entry.events.count > 100 {
                        Text("+ \(entry.events.count - 100) more events")
                            .font(Typo.caption)
                            .foregroundColor(DS.textTertiary)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.xs)
                    }
                }
                .padding(.leading, Spacing.xl)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(isHovered ? DS.bgHover.opacity(0.5) : DS.bgElevated.opacity(0.3))
                .animation(Anim.quick, value: isHovered)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(borderColor, lineWidth: 0.5)
        )
    }

    private var stateLabel: String {
        switch entry.agentState {
        case .working: return "working"
        case .needsInput: return "needs input"
        case .error: return "error"
        case .inactive: return "idle"
        }
    }

    private var borderColor: Color {
        switch entry.agentState {
        case .needsInput, .error:
            return DS.stateColor(for: entry.agentState).opacity(0.3)
        default:
            return DS.borderSubtle
        }
    }
}

// MARK: - Event Row

private struct ActivityEventRow: View {
    let event: ActivityEvent

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            // Timestamp
            Text(timeString)
                .font(Typo.captionMono)
                .foregroundColor(DS.textTertiary)
                .frame(width: 38, alignment: .trailing)

            // Icon
            Image(systemName: iconName)
                .font(.system(size: 9))
                .foregroundColor(iconColor)
                .frame(width: 14)

            // Description
            Text(description)
                .font(Typo.body)
                .foregroundColor(DS.textPrimary.opacity(0.85))
                .lineLimit(2)

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(isHovered ? DS.bgHover : Color.clear)
                .animation(Anim.quick, value: isHovered)
        )
        .onHover { isHovered = $0 }
    }

    private var timeString: String {
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
            return "Task completed (\(SessionStats.formatDuration(duration)))"
        case .fileRead(let path):
            return "Read \(shortenPath(path))"
        case .fileWrite(let path, let added, let removed):
            var s = shortenPath(path)
            if let a = added, let r = removed {
                s += " +\(a) -\(r)"
            }
            return s
        case .commandRun(let command):
            return truncate(command, max: 60)
        case .error(let message):
            return truncate(message, max: 80)
        case .modelChanged(let model):
            return "Model: \(model)"
        case .stateChanged(let from, let to):
            return "\(from.rawValue) \u{2192} \(to.rawValue)"
        case .subagentStarted(let name, let desc):
            let d = desc.isEmpty ? "" : " \u{2014} \(truncate(desc, max: 40))"
            return "Agent: \(name)\(d)"
        case .subagentCompleted(let name, let duration):
            return "Agent done: \(name) (\(SessionStats.formatDuration(duration)))"
        case .commandCompleted(let command, let exitCode, let duration):
            let cmd = truncate(command ?? "command", max: 40)
            let exit = exitCode.map { $0 == 0 ? " \u{2713}" : " [exit \($0)]" } ?? ""
            return "\(cmd)\(exit) (\(SessionStats.formatDuration(duration)))"
        }
    }

    private func shortenPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        if components.count <= 3 { return path }
        return components.suffix(3).joined(separator: "/")
    }

    private func truncate(_ s: String, max: Int) -> String {
        if s.count <= max { return s }
        return String(s.prefix(max)) + "\u{2026}"
    }
}
