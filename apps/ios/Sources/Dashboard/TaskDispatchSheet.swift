import SwiftUI

struct TaskDispatchSheet: View {
    @Binding var options: TaskDispatchOptions
    let agents: [AgentRunInfo]
    let recentDirectories: [String]
    var onLaunch: () -> Void
    var onCancel: () -> Void

    @State private var showAdvanced = false
    @State private var showDirectoryPicker = false
    @State private var isEditingTask = false

    private let cardBg = Color.white.opacity(0.08)
    private let border = Color.white.opacity(0.12)
    private let blue = Color(red: 0, green: 122 / 255, blue: 1)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("🚀 Launch Task").font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.top, 4)
                    taskSection; agentSection; directorySection; thinkingSection
                    advancedToggle
                    if showAdvanced { sessionSection; labelSection; modelSection; timeoutSection; contextSection }
                    launchButton
                }.padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(Color(red: 18 / 255, green: 18 / 255, blue: 20 / 255).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel).foregroundStyle(.gray)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    private func header(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 📝 Task

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("📝 Task")
            VStack(alignment: .leading, spacing: 8) {
                if isEditingTask {
                    TextEditor(text: $options.message).font(.system(size: 15))
                        .foregroundStyle(.white).scrollContentBackground(.hidden)
                        .frame(minHeight: 60, maxHeight: 120)
                } else {
                    Text(options.message).font(.system(size: 15)).foregroundStyle(.white).lineLimit(3)
                }
                HStack(spacing: 8) {
                    if options.source == .voice {
                        HStack(spacing: 4) {
                            Circle().fill(.red).frame(width: 6, height: 6)
                            Text("from voice").font(.system(size: 11)).foregroundStyle(.gray)
                        }
                    }
                    Spacer()
                    Button(isEditingTask ? "Done" : "✏️ Edit") {
                        withAnimation { isEditingTask.toggle() }
                    }.font(.system(size: 13, weight: .medium)).foregroundStyle(blue)
                }
            }.padding(12).modifier(CardStyle(bg: cardBg, stroke: border, radius: 12))
        }
    }

    // MARK: - 🤖 Agent

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("🤖 Agent")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    agentChip(id: nil, label: "⚡ Auto", subtitle: "recommended", dot: nil)
                    ForEach(agents) { a in
                        agentChip(id: a.id, label: a.displayName, subtitle: a.status.rawValue,
                                  dot: statusColor(a.status))
                    }
                }
            }
        }
    }

    private func agentChip(id: String?, label: String, subtitle: String, dot: Color?) -> some View {
        let sel = options.agentId == id
        return Button { options.agentId = id } label: {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
                    Text(label).font(.system(size: 13, weight: .medium))
                }
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.gray)
            }.padding(.horizontal, 12).padding(.vertical, 8)
                .modifier(CardStyle(bg: sel ? blue.opacity(0.15) : cardBg,
                                    stroke: sel ? blue : border, radius: 10,
                                    lineWidth: sel ? 1.5 : 1))
        }.foregroundStyle(.white)
    }

    private func statusColor(_ s: AgentStatus) -> Color {
        switch s { case .running: .green; case .idle: .gray; case .error: .red; case .planReview: .orange }
    }

    // MARK: - 📁 Working Directory

    private var directorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("📁 Working Directory")
            HStack {
                Text(options.workingDirectory ?? "~/").font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white).lineLimit(1)
                Spacer()
                Button("Change") { showDirectoryPicker = true }
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(blue)
            }.padding(10).modifier(CardStyle(bg: cardBg, stroke: border, radius: 10))
            if !recentDirectories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(recentDirectories, id: \.self) { dir in
                            Button { options.workingDirectory = dir } label: {
                                Text((dir as NSString).lastPathComponent).font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.white.opacity(0.06)).clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 🧠 Thinking Level

    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("🧠 Thinking Level")
            Picker("Thinking", selection: $options.thinking) {
                ForEach(ThinkingLevel.allCases, id: \.self) { Text($0.displayLabel).tag($0) }
            }.pickerStyle(.segmented)
        }
    }

    // MARK: - Advanced Toggle

    private var advancedToggle: some View {
        Button { withAnimation(.easeInOut(duration: 0.25)) { showAdvanced.toggle() } } label: {
            HStack(spacing: 4) { Text(showAdvanced ? "▾" : "▸"); Text("More Options") }
                .font(.system(size: 14, weight: .medium)).foregroundStyle(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 📋 Session

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("📋 Session")
            HStack(spacing: 10) {
                sessionCard("New Session", active: isNewSession) { options.sessionMode = .new }
                if case .continueExisting(_, let lbl) = options.sessionMode {
                    sessionCard("Continue: \(lbl ?? "session")", active: true) {}
                }
            }
        }
    }

    private var isNewSession: Bool { if case .new = options.sessionMode { true } else { false } }

    private func sessionCard(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(active ? blue : .clear)
                    .overlay(Circle().stroke(active ? blue : .gray, lineWidth: 1.5))
                    .frame(width: 10, height: 10)
                Text(label).font(.system(size: 13)).foregroundStyle(.white)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .modifier(CardStyle(bg: cardBg, stroke: active ? blue : border, radius: 10))
        }
    }

    // MARK: - 🏷 Label

    private var labelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("🏷 Label")
            TextField("Task label", text: Binding(
                get: { options.label ?? String(options.message.prefix(40)) },
                set: { options.label = $0 }
            )).font(.system(size: 14)).foregroundStyle(.white)
                .padding(10).modifier(CardStyle(bg: cardBg, stroke: border, radius: 10))
        }
    }

    // MARK: - 🤖 Model Override

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("🤖 Model Override")
            HStack {
                Text(options.model ?? "Agent default").font(.system(size: 14))
                    .foregroundStyle(options.model == nil ? .gray : .white)
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 12)).foregroundStyle(.gray)
            }.padding(10).modifier(CardStyle(bg: cardBg, stroke: border, radius: 10))
        }
    }

    // MARK: - ⏱ Timeout

    private var timeoutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("⏱ Timeout")
            HStack(spacing: 6) {
                ForEach(TimeoutPreset.allCases) { p in
                    let on = options.timeout == p.rawValue
                    Button { options.timeout = p.rawValue } label: {
                        Text(p.label).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(on ? blue.opacity(0.2) : cardBg).clipShape(Capsule())
                            .overlay(Capsule().stroke(on ? blue : border, lineWidth: 1))
                    }
                }
            }
        }
    }

    // MARK: - 📎 Extra Context

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("📎 Extra Context")
            TextEditor(text: Binding(
                get: { options.extraContext ?? "" },
                set: { options.extraContext = $0.isEmpty ? nil : $0 }
            )).font(.system(size: 14)).foregroundStyle(.white).scrollContentBackground(.hidden)
                .frame(minHeight: 60, maxHeight: 100).padding(8)
                .modifier(CardStyle(bg: cardBg, stroke: border, radius: 10))
        }
    }

    // MARK: - 🚀 Launch Button

    private var launchButton: some View {
        Button(action: onLaunch) {
            Text("🚀 Launch Task").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(LinearGradient(colors: [blue, Color(red: 137 / 255, green: 68 / 255, blue: 1)],
                                           startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }.padding(.top, 4)
    }
}

// MARK: - Card Style Modifier

private struct CardStyle: ViewModifier {
    let bg: Color; let stroke: Color; let radius: CGFloat; var lineWidth: CGFloat = 1
    func body(content: Content) -> some View {
        content.background(bg).clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(stroke, lineWidth: lineWidth))
    }
}

// MARK: - Preview

#Preview {
    Color.black.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            TaskDispatchSheet(
                options: .constant(TaskDispatchOptions(message: "Fix the login bug in src/auth.ts")),
                agents: [
                    AgentRunInfo(id: "main", name: "Main", status: .idle),
                    AgentRunInfo(id: "research", name: "Research", status: .running),
                ],
                recentDirectories: ["~/projects/app", "~/Desktop/repo"],
                onLaunch: {}, onCancel: {}
            )
        }.preferredColorScheme(.dark)
}
