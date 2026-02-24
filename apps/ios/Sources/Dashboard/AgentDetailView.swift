import SwiftUI

struct AgentDetailView: View {
    let agent: AgentRunInfo

    @Environment(NodeAppModel.self) private var appModel
    @Environment(DashboardController.self) private var dashboard

    @State private var selectedSegment = 0
    @State private var messageText = ""
    @State private var toolEvents: [AgentToolEvent] = Self.mockEvents

    private let segments = ["Tool Calls", "Output Log", "Files Changed"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    detailHeader
                    segmentControl
                    segmentContent
                }
                .padding(16)
            }
            chatInput
        }
        .background(Color.black)
        .navigationTitle(agent.displayName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Stop") {
                    // TODO: wire to dashboard.stopAgent
                }
                .foregroundColor(.red)
                .font(.system(size: 15, weight: .semibold))
            }
        }
    }

    // MARK: - Detail Header

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailRow(label: "Status", value: statusText)
            detailRow(label: "Task", value: agent.currentTask ?? "—")
            detailRow(label: "Elapsed", value: formattedElapsed)
            detailRow(label: "Session", value: agent.sessionKey ?? "—")
            progressBar
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.5))
                .frame(width: 64, alignment: .leading)
            if label == "Status" {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
            }
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 6)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * (agent.progress ?? 0), height: 6)
            }
        }
        .frame(height: 6)
        .overlay(alignment: .trailing) {
            if let progress = agent.progress {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(white: 0.5))
                    .offset(y: 12)
            }
        }
        .padding(.bottom, agent.progress != nil ? 14 : 0)
    }

    // MARK: - Segment Control

    private var segmentControl: some View {
        HStack(spacing: 4) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, title in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedSegment = index }
                } label: {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(selectedSegment == index ? .white : Color(white: 0.5))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            selectedSegment == index
                                ? Color.white.opacity(0.12)
                                : Color.clear
                        )
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.06))
        .cornerRadius(10)
    }

    @ViewBuilder
    private var segmentContent: some View {
        switch selectedSegment {
        case 0:
            AgentEventTimeline(events: toolEvents)
        case 1:
            placeholderText("Real-time output will appear here...")
        default:
            placeholderText("Modified files will be listed here...")
        }
    }

    private func placeholderText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundColor(Color(white: 0.4))
            .frame(maxWidth: .infinity, minHeight: 120)
    }

    // MARK: - Chat Input

    private var chatInput: some View {
        HStack(spacing: 10) {
            TextField("Message this agent...", text: $messageText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06))
                .cornerRadius(12)
            Button {
                guard !messageText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                let msg = messageText
                messageText = ""
                Task {
                    await dashboard.dispatchTask(
                        message: msg,
                        agentId: agent.id,
                        appModel: appModel
                    )
                }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.blue)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.95))
    }

    // MARK: - Helpers

    private var statusText: String {
        switch agent.status {
        case .running: "Running"
        case .idle: "Idle"
        case .error: "Error"
        case .planReview: "Awaiting Review"
        }
    }

    private var statusDotColor: Color {
        switch agent.status {
        case .running: .green
        case .idle: Color(white: 0.4)
        case .error: .red
        case .planReview: .orange
        }
    }

    private var formattedElapsed: String {
        guard let s = agent.elapsedSeconds else { return "—" }
        let mins = s / 60, secs = s % 60
        return "\(mins)m \(secs)s"
    }

    // MARK: - Mock Data

    private static let mockEvents: [AgentToolEvent] = [
        AgentToolEvent(
            id: "ev-1", kind: .thinking,
            title: "Thinking", detail: "Analyzing code structure...",
            codeSnippet: nil,
            timestamp: Date().addingTimeInterval(-240), isInProgress: false
        ),
        AgentToolEvent(
            id: "ev-2", kind: .readFile,
            title: "Read: src/auth/login.ts", detail: nil,
            codeSnippet: nil,
            timestamp: Date().addingTimeInterval(-180), isInProgress: false
        ),
        AgentToolEvent(
            id: "ev-3", kind: .editFile,
            title: "Edit: src/auth/login.ts",
            detail: "Updated token refresh logic",
            codeSnippet: """
            - const token = await getToken();
            + const token = await refreshToken({ force: true });
            """,
            timestamp: Date().addingTimeInterval(-90), isInProgress: false
        ),
        AgentToolEvent(
            id: "ev-4", kind: .bash,
            title: "Bash: npm test -- auth",
            detail: "✅ 12/12 tests passed",
            codeSnippet: nil,
            timestamp: Date().addingTimeInterval(-30), isInProgress: true
        ),
    ]
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AgentDetailView(agent: AgentRunInfo(
            id: "ralph",
            name: "ralph",
            status: .running,
            currentTask: "Refactoring auth module",
            elapsedSeconds: 263,
            progress: 0.72,
            lastToolCall: "edit src/auth.ts",
            sessionKey: "sess_8f2a"
        ))
    }
    .preferredColorScheme(.dark)
}
