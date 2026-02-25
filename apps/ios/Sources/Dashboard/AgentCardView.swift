import SwiftUI

struct AgentCardView: View {
    let agent: AgentRunInfo
    var onTap: () -> Void = {}
    var onRetry: () -> Void = {}
    var onDispatch: () -> Void = {}
    var onViewPlan: () -> Void = {}
    var onApprovePlan: () -> Void = {}
    var onRejectPlan: () -> Void = {}

    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            switch agent.status {
            case .running: runningContent
            case .error: errorContent
            case .planReview: planReviewContent
            case .idle: idleContent
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isPressed)
        .onTapGesture { onTap() }
        .onLongPressGesture(minimumDuration: .infinity, pressing: { isPressed = $0 }, perform: {})
        .padding(.bottom, 0)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Circle()
                .fill(statusDotColor)
                .frame(width: 10, height: 10)
            Text(agent.displayName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            Spacer()
            statusBadge
        }
    }

    private var statusBadge: some View {
        Text(statusLabel)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(statusAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(statusAccent.opacity(0.15))
            .cornerRadius(8)
    }

    // MARK: - Running

    private var runningContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let task = agent.currentTask {
                Text(task)
                    .font(.system(size: 15))
                    .foregroundColor(Color(white: 0.78))
            }
            metaRow
            progressBar
        }
    }

    private var metaRow: some View {
        HStack(spacing: 0) {
            if let elapsed = agent.elapsedSeconds {
                Label(formattedTime(elapsed), systemImage: "timer")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 0.39, green: 0.39, blue: 0.40))
            }
            if agent.elapsedSeconds != nil, agent.lastToolCall != nil {
                Text("  │  ")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 0.39, green: 0.39, blue: 0.40))
            }
            if let tool = agent.lastToolCall {
                Label(tool, systemImage: "wrench")
                    .font(.system(size: 13))
                    .foregroundColor(Color(red: 0.39, green: 0.39, blue: 0.40))
            }
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
                            colors: [Color.green, Color.green.opacity(0.8)],
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
        .padding(.bottom, progress != nil ? 14 : 0)
    }

    private var progress: Double? { agent.progress }

    // MARK: - Error

    private var errorContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let task = agent.currentTask {
                Label(task, systemImage: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(Color.red.opacity(0.9))
            }
            if let error = agent.errorMessage {
                Text(error)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color.red.opacity(0.85))
                    .lineLimit(3)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(8)
            }
            HStack(spacing: 10) {
                Spacer()
                actionButton(label: "🔄 Retry", color: .orange, action: onRetry)
                actionButton(label: "View Log", color: Color(white: 0.4), action: onTap)
            }
        }
    }

    // MARK: - Plan Review

    private var planReviewContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let task = agent.currentTask {
                Label(task, systemImage: "pause.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(Color(white: 0.78))
            }
            HStack(spacing: 8) {
                Spacer()
                actionButton(label: "View Plan", color: Color(white: 0.35), action: onViewPlan)
                actionButton(label: "✅ Approve", color: .green, action: onApprovePlan)
                actionButton(label: "Reject", color: .red.opacity(0.8), action: onRejectPlan)
            }
        }
    }

    // MARK: - Idle

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Waiting for tasks...")
                .font(.system(size: 15))
                .foregroundColor(Color(white: 0.5))
            HStack {
                Spacer()
                actionButton(label: "📋 Dispatch", color: .blue, action: onDispatch)
            }
        }
    }

    // MARK: - Helpers

    private func actionButton(label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(color.opacity(0.25))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var statusDotColor: Color {
        switch agent.status {
        case .running: return .green
        case .error: return .red
        case .planReview: return .orange
        case .idle: return Color(white: 0.5)
        }
    }

    private var statusAccent: Color {
        switch agent.status {
        case .running: return .green
        case .error: return .red
        case .planReview: return .orange
        case .idle: return .gray
        }
    }

    private var statusLabel: String {
        switch agent.status {
        case .running: return "Running"
        case .error: return "Error"
        case .planReview: return "Awaiting"
        case .idle: return "Idle"
        }
    }

    private func formattedTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return "\(m)m\(String(format: "%02d", s))s"
    }
}
