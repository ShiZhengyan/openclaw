import OpenClawChatUI
import OpenClawKit
import SwiftUI

struct ChatSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: OpenClawChatViewModel
    @State private var showSessionDrawer = false
    private let userAccent: Color?
    private let agentName: String?

    init(gateway: GatewayNodeSession, sessionKey: String, agentName: String? = nil, userAccent: Color? = nil) {
        let transport = IOSGatewayChatTransport(gateway: gateway)
        self._viewModel = State(
            initialValue: OpenClawChatViewModel(
                sessionKey: sessionKey,
                transport: transport))
        self.userAccent = userAccent
        self.agentName = agentName
    }

    var body: some View {
        NavigationStack {
            OpenClawChatView(
                viewModel: self.viewModel,
                showsSessionSwitcher: false,
                userAccent: self.userAccent)
                .navigationTitle(self.chatTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            self.viewModel.refreshSessions(limit: 200)
                            self.showSessionDrawer = true
                        } label: {
                            Image(systemName: "line.3.horizontal")
                        }
                        .accessibilityLabel("Sessions")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            self.startNewChat()
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("New Chat")

                        Button {
                            self.dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close")
                    }
                }
        }
        .sheet(isPresented: self.$showSessionDrawer) {
            ChatSessionDrawer(
                viewModel: self.viewModel,
                onNewChat: {
                    self.showSessionDrawer = false
                    self.startNewChat()
                },
                onSelectSession: { key in
                    self.showSessionDrawer = false
                    self.viewModel.switchSession(to: key)
                })
        }
    }

    private var chatTitle: String {
        let key = self.viewModel.sessionKey
        let friendlyKey = OpenClawChatSessionEntry.formatSessionKey(key)
        let trimmed = (self.agentName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Chat (\(friendlyKey))" }
        return "Chat (\(trimmed))"
    }

    private func startNewChat() {
        let newKey = "chat-\(UUID().uuidString.prefix(8).lowercased())"
        self.viewModel.switchSession(to: newKey)
    }
}

// MARK: - Session Drawer

private struct ChatSessionDrawer: View {
    @Bindable var viewModel: OpenClawChatViewModel
    var onNewChat: () -> Void
    var onSelectSession: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // New Chat button
                Section {
                    Button(action: self.onNewChat) {
                        Label("New Chat", systemImage: "plus.bubble")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                }

                // Sessions grouped by date
                ForEach(self.groupedSessions, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.sessions) { session in
                            Button {
                                self.onSelectSession(session.key)
                            } label: {
                                HStack(spacing: 10) {
                                    if session.key == self.viewModel.sessionKey {
                                        Circle()
                                            .fill(.green)
                                            .frame(width: 8, height: 8)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.friendlyName)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        if let subject = session.subject,
                                           !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        {
                                            Text(subject)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer(minLength: 0)

                                    if let ts = session.relativeTimestamp {
                                        Text(ts)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        self.viewModel.refreshSessions(limit: 200)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        self.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .onAppear {
                self.viewModel.refreshSessions(limit: 200)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Grouping

    private struct SessionGroup {
        let title: String
        let sessions: [OpenClawChatSessionEntry]
    }

    private var groupedSessions: [SessionGroup] {
        let choices = self.viewModel.sessionChoices
        let now = Date()
        let calendar = Calendar.current

        var today: [OpenClawChatSessionEntry] = []
        var yesterday: [OpenClawChatSessionEntry] = []
        var thisWeek: [OpenClawChatSessionEntry] = []
        var older: [OpenClawChatSessionEntry] = []

        for session in choices {
            guard let updatedAt = session.updatedAt, updatedAt > 0 else {
                older.append(session)
                continue
            }
            let date = Date(timeIntervalSince1970: updatedAt / 1000)
            if calendar.isDateInToday(date) {
                today.append(session)
            } else if calendar.isDateInYesterday(date) {
                yesterday.append(session)
            } else if now.timeIntervalSince(date) < 7 * 86400 {
                thisWeek.append(session)
            } else {
                older.append(session)
            }
        }

        var groups: [SessionGroup] = []
        if !today.isEmpty { groups.append(SessionGroup(title: "Today", sessions: today)) }
        if !yesterday.isEmpty { groups.append(SessionGroup(title: "Yesterday", sessions: yesterday)) }
        if !thisWeek.isEmpty { groups.append(SessionGroup(title: "This Week", sessions: thisWeek)) }
        if !older.isEmpty { groups.append(SessionGroup(title: "Older", sessions: older)) }
        return groups
    }
}
