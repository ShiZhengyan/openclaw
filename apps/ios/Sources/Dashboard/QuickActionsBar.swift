import SwiftUI

struct QuickActionsBar: View {
    var onQuickAction: (QuickAction) -> Void
    var onQuickActionLongPress: (QuickAction) -> Void

    @State private var confirmedAction: QuickAction?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(QuickAction.allCases) { action in
                    chip(for: action)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func chip(for action: QuickAction) -> some View {
        let isConfirmed = confirmedAction == action

        return Button {
            onQuickAction(action)
            withAnimation(.easeInOut(duration: 0.15)) { confirmedAction = action }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.2)) { confirmedAction = nil }
            }
        } label: {
            HStack(spacing: 4) {
                Text(isConfirmed ? "✅" : action.emoji)
                Text(action.label)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(white: 0.9))
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in onQuickActionLongPress(action) }
        )
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        QuickActionsBar(onQuickAction: { _ in }, onQuickActionLongPress: { _ in })
    }
    .preferredColorScheme(.dark)
}
