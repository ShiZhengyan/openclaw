import SwiftUI

struct TaskDispatchBar: View {
    @Binding var text: String
    var isRecording: Bool
    /// Tap send → open dispatch sheet.
    var onSubmit: (String) -> Void
    /// Long-press send → quick launch with defaults (no sheet).
    var onQuickLaunch: (String) -> Void
    var onMicTap: () -> Void
    var onQuickAction: (QuickAction) -> Void
    var onQuickActionLongPress: (QuickAction) -> Void

    @FocusState private var isFocused: Bool
    @State private var pulseScale: CGFloat = 1.0

    private let barBackground = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).opacity(0.98)
    private let fieldBackground = Color.white.opacity(0.08)
    private let fieldBorder = Color.white.opacity(0.12)
    private let micBlue = Color(red: 0, green: 122 / 255, blue: 1)
    private let micGreen = Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)

    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.white.opacity(0.08).frame(height: 1)

            // Quick actions row
            QuickActionsBar(
                onQuickAction: onQuickAction,
                onQuickActionLongPress: onQuickActionLongPress)

            // Input row
            HStack(spacing: 10) {
                inputField

                // Send button — tap opens sheet, long-press quick launches
                if hasText {
                    sendButton
                }

                micButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 4)

            // Hint text
            if hasText {
                Text("Tap ↑ to configure · Hold ↑ to quick launch")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.28))
                    .padding(.bottom, 4)
            }
        }
        .background(barBackground)
    }

    // MARK: - Input Field

    private var inputField: some View {
        TextField("Dispatch a task...", text: $text)
            .focused($isFocused)
            .onSubmit { submitText() }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(fieldBackground)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(fieldBorder, lineWidth: 1))
            .foregroundStyle(.white)
            .tint(.white)
    }

    // MARK: - Send Button

    private var sendButton: some View {
        Button {
            submitText()
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.blue)
                .clipShape(Circle())
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in quickLaunch() }
        )
    }

    // MARK: - Mic Button

    private var micButton: some View {
        let color = isRecording ? micGreen : micBlue

        return Button(action: onMicTap) {
            Image(systemName: isRecording ? "mic.fill" : "mic")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(color)
                .clipShape(Circle())
                .scaleEffect(isRecording ? pulseScale : 1.0)
                .shadow(
                    color: isRecording ? micGreen.opacity(0.6) : .clear,
                    radius: isRecording ? 10 * pulseScale : 0)
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseScale = 1.15
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { pulseScale = 1.0 }
            }
        }
    }

    // MARK: - Actions

    private func submitText() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        isFocused = false
    }

    private func quickLaunch() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onQuickLaunch(trimmed)
        text = ""
        isFocused = false
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            TaskDispatchBar(
                text: .constant("Write a user registration feature"),
                isRecording: false,
                onSubmit: { _ in },
                onQuickLaunch: { _ in },
                onMicTap: {},
                onQuickAction: { _ in },
                onQuickActionLongPress: { _ in })
        }
    }
    .preferredColorScheme(.dark)
}
