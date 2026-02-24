import SwiftUI

struct AgentEventTimeline: View {
    let events: [AgentToolEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                TimelineItemView(
                    event: event,
                    isLast: index == events.count - 1
                )
            }
        }
    }
}

// MARK: - Timeline Item

private struct TimelineItemView: View {
    let event: AgentToolEvent
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Dot + connecting line
            VStack(spacing: 0) {
                TimelineDot(kind: event.kind, isInProgress: event.isInProgress)
                if !isLast {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 24)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                if let detail = event.detail {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(red: 0.39, green: 0.39, blue: 0.40)) // #636366
                }

                if let snippet = event.codeSnippet {
                    CodeSnippetView(code: snippet)
                }

                TimestampLabel(date: event.timestamp)
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
    }
}

// MARK: - Timeline Dot

private struct TimelineDot: View {
    let kind: AgentToolEvent.Kind
    let isInProgress: Bool

    @State private var isPulsing = false

    private var emoji: String {
        switch kind {
        case .thinking: "🤔"
        case .readFile: "📖"
        case .editFile: "✏️"
        case .bash:     "⚡"
        case .search:   "🔍"
        case .other:    "⚙️"
        }
    }

    private var dotColor: Color {
        switch kind {
        case .thinking:  Color(red: 175/255, green: 82/255, blue: 222/255).opacity(0.2)
        case .readFile:  Color(red: 0, green: 122/255, blue: 1).opacity(0.2)
        case .editFile:  Color(red: 1, green: 159/255, blue: 10/255).opacity(0.2)
        case .bash:      Color(red: 0, green: 122/255, blue: 1).opacity(0.2)
        case .search:    Color(red: 0, green: 122/255, blue: 1).opacity(0.2)
        case .other:     Color.gray.opacity(0.2)
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(dotColor)
                .frame(width: 24, height: 24)
                .scaleEffect(isInProgress && isPulsing ? 1.3 : 1.0)
                .opacity(isInProgress && isPulsing ? 0.5 : 1.0)

            Text(emoji)
                .font(.system(size: 12))
        }
        .animation(
            isInProgress
                ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                : .default,
            value: isPulsing
        )
        .onAppear {
            if isInProgress { isPulsing = true }
        }
        .onChange(of: isInProgress) { _, newValue in
            isPulsing = newValue
        }
    }
}

// MARK: - Code Snippet

private struct CodeSnippetView: View {
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(code.components(separatedBy: "\n"), id: \.self) { line in
                DiffLineView(line: line)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct DiffLineView: View {
    let line: String

    private var style: (color: Color, strikethrough: Bool) {
        if line.hasPrefix("+ ") || line.hasPrefix("+\t") {
            return (.green, false)
        } else if line.hasPrefix("- ") || line.hasPrefix("-\t") {
            return (.red, true)
        }
        return (Color(red: 0.39, green: 0.39, blue: 0.40), false)
    }

    var body: some View {
        Text(line)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(style.color)
            .strikethrough(style.strikethrough, color: style.color)
    }
}

// MARK: - Timestamp

private struct TimestampLabel: View {
    let date: Date

    private var relativeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    var body: some View {
        Text(relativeText)
            .font(.system(size: 12))
            .foregroundStyle(Color(red: 0.28, green: 0.28, blue: 0.29)) // #48484a
    }
}

#Preview {
    ScrollView {
        AgentEventTimeline(events: [
            .init(id: "1", kind: .thinking, title: "Analyzing code structure...",
                  detail: "Understanding auth module architecture", codeSnippet: nil,
                  timestamp: Date().addingTimeInterval(-120), isInProgress: false),
            .init(id: "2", kind: .readFile, title: "Read: src/auth/login.ts",
                  detail: "142 lines · Read complete", codeSnippet: nil,
                  timestamp: Date().addingTimeInterval(-105), isInProgress: false),
            .init(id: "3", kind: .editFile, title: "Edit: src/auth/login.ts", detail: nil,
                  codeSnippet: "- const expiry = '1h'\n+ const expiry = '24h'\n+ const refresh = '7d'",
                  timestamp: Date().addingTimeInterval(-80), isInProgress: false),
            .init(id: "4", kind: .bash, title: "Bash: npm test -- auth",
                  detail: "✅ 12/12 tests passed (2.3s)", codeSnippet: nil,
                  timestamp: Date().addingTimeInterval(-50), isInProgress: true),
        ]).padding()
    }.background(.black)
}
