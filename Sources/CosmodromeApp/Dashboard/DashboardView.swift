import Core
import SwiftUI

/// Main dashboard view — shows all Ghostty sessions grouped by project.
/// No terminal rendering, just project/session management and agent status.
struct DashboardView: View {
    @Bindable var registry: DashboardRegistry
    var onFocusSession: (GhosttySession) -> Void
    var onRenameProject: (DashboardProject, String) -> Void

    @State private var selectedProjectId: UUID?
    @State private var hoveredSessionId: UUID?

    var body: some View {
        HSplitView {
            // Left: Project list
            projectList
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            // Right: Session grid for selected project
            sessionGrid
                .frame(minWidth: 400)
        }
        .frame(minWidth: 700, minHeight: 400)
    }

    // MARK: - Project List

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "rocket.fill")
                    .foregroundColor(.orange)
                Text("Cosmodrome")
                    .font(Typo.title)
                    .foregroundColor(DS.textPrimary)
                Spacer()
                if let count = ghosttyStatus {
                    Text(count)
                        .font(Typo.body)
                        .foregroundColor(DS.textTertiary)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)

            Divider().opacity(0.3)

            if registry.projects.isEmpty {
                VStack(spacing: Spacing.md) {
                    Spacer()
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 40))
                        .foregroundColor(DS.textTertiary)
                    Text("No sessions detected")
                        .font(Typo.subheading)
                        .foregroundColor(DS.textSecondary)
                    Text("Open Ghostty and source the\nshell integration script")
                        .font(Typo.body)
                        .foregroundColor(DS.textTertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(registry.projects, id: \.id) { project in
                            DashboardProjectRow(
                                project: project,
                                isSelected: project.id == effectiveProjectId,
                                onSelect: { selectedProjectId = project.id },
                                onRename: { newName in onRenameProject(project, newName) }
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.top, Spacing.sm)
                }
            }
        }
        .background(DS.bgSidebar)
    }

    // MARK: - Session Grid

    private var sessionGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let project = selectedProject {
                // Header
                HStack {
                    Circle()
                        .fill(Color(hex: project.color) ?? .blue)
                        .frame(width: 10, height: 10)
                    Text(project.name)
                        .font(Typo.largeTitle)
                        .foregroundColor(DS.textPrimary)
                    Text(project.rootPath)
                        .font(Typo.body)
                        .foregroundColor(DS.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text("\(project.sessions.count) session\(project.sessions.count == 1 ? "" : "s")")
                        .font(Typo.body)
                        .foregroundColor(DS.textTertiary)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)

                Divider().opacity(0.3)

                // Sessions
                ScrollView {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(project.sessions, id: \.id) { session in
                            DashboardSessionCard(
                                session: session,
                                isHovered: hoveredSessionId == session.id,
                                onFocus: { onFocusSession(session) }
                            )
                            .onHover { isHovered in
                                hoveredSessionId = isHovered ? session.id : nil
                            }
                        }
                    }
                    .padding(Spacing.lg)
                }
            } else {
                VStack {
                    Spacer()
                    Text("Select a project")
                        .font(Typo.subheading)
                        .foregroundColor(DS.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(DS.bgPrimary)
    }

    // MARK: - Helpers

    private var effectiveProjectId: UUID? {
        selectedProjectId ?? registry.projects.first?.id
    }

    private var selectedProject: DashboardProject? {
        guard let id = effectiveProjectId else { return nil }
        return registry.projects.first { $0.id == id }
    }

    private var ghosttyStatus: String? {
        let total = registry.projects.flatMap(\.sessions).count
        guard total > 0 else { return nil }
        let agents = registry.projects.flatMap(\.sessions).filter(\.isAgent).count
        if agents > 0 {
            return "\(total) sessions, \(agents) agents"
        }
        return "\(total) sessions"
    }
}

// MARK: - Project Row

private struct DashboardProjectRow: View {
    let project: DashboardProject
    let isSelected: Bool
    var onSelect: () -> Void
    var onRename: (String) -> Void

    @State private var isEditing = false
    @State private var editName = ""
    @State private var isHovered = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(Color(hex: project.color) ?? .blue)
                .frame(width: 8, height: 8)

            if isEditing {
                TextField("Name", text: $editName, onCommit: {
                    if !editName.trimmingCharacters(in: .whitespaces).isEmpty {
                        onRename(editName.trimmingCharacters(in: .whitespaces))
                    }
                    isEditing = false
                })
                .textFieldStyle(.plain)
                .font(Typo.subheading)
                .foregroundColor(DS.textPrimary)
                .focused($isNameFocused)
                .onAppear { isNameFocused = true }
                .onExitCommand { isEditing = false }
            } else {
                Text(project.name)
                    .font(Typo.subheading)
                    .foregroundColor(isSelected ? DS.textPrimary : DS.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(project.sessions.count)")
                .font(Typo.body)
                .foregroundColor(DS.textTertiary)

            if project.aggregateState != .inactive {
                Circle()
                    .fill(DS.stateColor(for: project.aggregateState))
                    .frame(width: 6, height: 6)
            }

            if project.attentionCount > 0 {
                Text("\(project.attentionCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(DS.stateError))
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(isSelected ? DS.bgSelected : (isHovered ? DS.bgHover : Color.clear))
                .animation(Anim.quick, value: isSelected)
                .animation(Anim.quick, value: isHovered)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            editName = project.name
            isEditing = true
        }
        .onTapGesture(count: 1) {
            if !isEditing { onSelect() }
        }
    }
}

// MARK: - Session Card

private struct DashboardSessionCard: View {
    let session: GhosttySession
    let isHovered: Bool
    var onFocus: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Agent state indicator
            VStack {
                if session.isAgent {
                    Image(systemName: "cpu")
                        .font(.system(size: 16))
                        .foregroundColor(DS.stateColor(for: session.agentState))
                } else {
                    Image(systemName: "terminal")
                        .font(.system(size: 16))
                        .foregroundColor(DS.textTertiary)
                }
            }
            .frame(width: 32)

            // Session info
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(session.label)
                        .font(Typo.subheadingMedium)
                        .foregroundColor(DS.textPrimary)

                    if session.isAgent, let type = session.agentType {
                        Text(type)
                            .font(Typo.footnoteMedium)
                            .foregroundColor(DS.textPrimary.opacity(0.8))
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(DS.stateColor(for: session.agentState).opacity(0.2))
                            )
                    }

                    if session.isAgent, let model = session.agentModel {
                        Text(model)
                            .font(Typo.footnote)
                            .foregroundColor(DS.textTertiary)
                    }
                }

                Text(session.cwd)
                    .font(Typo.body)
                    .foregroundColor(DS.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: Spacing.sm) {
                    Text("PID \(session.pid)")
                        .font(Typo.footnote)
                        .foregroundColor(DS.textTertiary)

                    if session.isAgent {
                        Text(stateLabel(session.agentState))
                            .font(Typo.footnoteMedium)
                            .foregroundColor(DS.stateColor(for: session.agentState))
                    }

                    if !session.isAlive {
                        Text("disconnected")
                            .font(Typo.footnote)
                            .foregroundColor(DS.stateError.opacity(0.8))
                    }
                }
            }

            Spacer()

            // Focus button
            Button(action: onFocus) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.up.forward.app")
                    Text("Focus")
                }
                .font(Typo.bodyMedium)
                .foregroundColor(DS.textPrimary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs + 1)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(DS.accent.opacity(isHovered ? 0.7 : 0.4))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(isHovered ? DS.bgHover : DS.borderSubtle)
                .animation(Anim.quick, value: isHovered)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(
                    session.agentState == .needsInput ? DS.stateNeedsInput.opacity(0.35) :
                    session.agentState == .error ? DS.stateError.opacity(0.35) :
                    DS.borderSubtle,
                    lineWidth: 1
                )
        )
    }

    private func stateLabel(_ state: AgentState) -> String {
        switch state {
        case .working: return "working"
        case .needsInput: return "needs input"
        case .error: return "error"
        case .inactive: return "idle"
        }
    }
}
