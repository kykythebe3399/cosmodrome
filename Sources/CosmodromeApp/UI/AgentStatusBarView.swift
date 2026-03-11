import Core
import SwiftUI

struct AgentStatusBarView: View {
    @Bindable var projectStore: ProjectStore
    var onJumpToSession: (UUID, UUID) -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            ForEach(agentEntries, id: \.sessionId) { entry in
                AgentStatusEntry(
                    projectName: entry.projectName,
                    sessionName: entry.sessionName,
                    state: entry.state,
                    model: entry.model
                )
                .onTapGesture {
                    onJumpToSession(entry.projectId, entry.sessionId)
                }
            }

            Spacer()

            // Session count
            Text("\(totalSessionCount) sessions")
                .font(Typo.body)
                .foregroundColor(DS.textTertiary)
        }
        .padding(.horizontal, Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.bgSidebar)
    }

    private struct AgentInfo: Identifiable {
        let id = UUID()
        let projectId: UUID
        let projectName: String
        let sessionId: UUID
        let sessionName: String
        let state: AgentState
        let model: String?
    }

    private var agentEntries: [AgentInfo] {
        projectStore.projects.flatMap { project in
            project.sessions
                .filter { $0.isAgent && $0.agentState != .inactive }
                .map { session in
                    AgentInfo(
                        projectId: project.id,
                        projectName: project.name,
                        sessionId: session.id,
                        sessionName: session.name,
                        state: session.agentState,
                        model: session.agentModel
                    )
                }
        }
    }

    private var totalSessionCount: Int {
        projectStore.projects.reduce(0) { $0 + $1.sessions.count }
    }
}

private struct AgentStatusEntry: View {
    let projectName: String
    let sessionName: String
    let state: AgentState
    let model: String?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(stateColor)
                .frame(width: 6, height: 6)
                .shadow(color: stateColor.opacity(0.4), radius: 3)

            Text(statusText)
                .font(Typo.body)
                .foregroundColor(DS.textPrimary.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            Capsule()
                .fill(stateColor.opacity(isHovered ? 0.25 : 0.12))
                .animation(Anim.quick, value: isHovered)
        )
        .overlay(
            Capsule()
                .stroke(stateColor.opacity(isHovered ? 0.3 : 0), lineWidth: 1)
                .animation(Anim.quick, value: isHovered)
        )
        .onHover { isHovered = $0 }
        .help("\(projectName)/\(sessionName)")

    }

    private var statusText: String {
        var text = "\(projectName)/\(sessionName)"
        if let model {
            text += " \(model)"
        }
        let stateLabel: String
        switch state {
        case .working: stateLabel = "working"
        case .needsInput: stateLabel = "input"
        case .error: stateLabel = "error"
        case .inactive: stateLabel = ""
        }
        if !stateLabel.isEmpty {
            text += " \(stateLabel)"
        }
        return text
    }

    private var stateColor: Color {
        DS.stateColor(for: state)
    }
}
