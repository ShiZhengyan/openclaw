import SwiftUI

@MainActor
struct SummaryBar: View {
    let summary: DashboardSummary
    var onFilterTap: (AgentStatus?) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 0) {
            statItem(count: summary.running, label: "Run", color: .green, status: .running)
            divider
            statItem(count: summary.idle, label: "Idle", color: Color(hex: 0x8B8BA3), status: .idle)
            divider
            statItem(count: summary.error, label: "Err", color: .red, status: .error)
            divider
            statItem(count: summary.queued, label: "Queue", color: .blue, status: nil)
        }
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .preferredColorScheme(.dark)
    }

    private func statItem(count: Int, label: String, color: Color, status: AgentStatus?) -> some View {
        Button {
            onFilterTap(status)
        } label: {
            VStack(spacing: 4) {
                Text("\(count)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x8B8BA3))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 8)
    }
}

private extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

#Preview {
    SummaryBar(summary: DashboardSummary(running: 3, idle: 1, error: 1, queued: 4))
        .padding()
        .background(Color.black)
}
