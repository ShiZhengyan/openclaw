import SwiftUI

struct TaskDispatchBar: View {
    @Binding var text: String
    var isRecording: Bool
    var onSubmit: (String) -> Void
    var onMicTap: () -> Void

    @FocusState private var isFocused: Bool
    @State private var pulseScale: CGFloat = 1.0

    private let barBackground = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).opacity(0.98)
    private let topBorder = Color.white.opacity(0.08)
    private let fieldBackground = Color.white.opacity(0.08)
    private let fieldBorder = Color.white.opacity(0.12)
    private let micBlue = Color(red: 0, green: 122 / 255, blue: 1)
    private let micGreen = Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)

    var body: some View {
        VStack(spacing: 0) {
            topBorder.frame(height: 1)

            HStack(spacing: 12) {
                inputField
                micButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background(barBackground)
    }

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
                .shadow(color: isRecording ? micGreen.opacity(0.6) : .clear, radius: isRecording ? 10 * pulseScale : 0)
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

    private func submitText() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
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
                text: .constant(""),
                isRecording: false,
                onSubmit: { _ in },
                onMicTap: {}
            )
        }
    }
    .preferredColorScheme(.dark)
}
