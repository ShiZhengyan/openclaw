import SwiftUI

struct TaskQueueView: View {
    let items: [TaskQueueItem]
    var onMoveUp: (String) -> Void = { _ in }
    var onMoveDown: (String) -> Void = { _ in }
    var onCancel: (String) -> Void = { _ in }
    var onAddTask: (String) -> Void = { _ in }

    @State private var newTaskText = ""

    private var executing: [TaskQueueItem] { items.filter { $0.status == .executing } }
    private var queued: [TaskQueueItem] { items.filter { $0.status == .queued } }
    private var completed: [TaskQueueItem] { items.filter { $0.status == .completed } }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !executing.isEmpty { section("EXECUTING", executing.count) { ForEach(executing) { executingCard($0) } } }
                    if !queued.isEmpty { section("QUEUED", queued.count) {
                        ForEach(Array(queued.enumerated()), id: \.element.id) { i, item in queuedCard(item, index: i + 1) }
                    }}
                    if !completed.isEmpty { section("COMPLETED", completed.count) { ForEach(completed) { completedCard($0) } } }
                }.padding(16).padding(.bottom, 72)
            }
            dispatchBar
        }
        .background(Color.black)
        .navigationTitle("Task Queue (\(items.count))")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Section

    private func section<C: View>(_ title: String, _ count: Int, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(title) (\(count))").font(.system(size: 13, weight: .semibold)).tracking(1.2).foregroundColor(.gray)
            content()
        }
    }

    private func cardBackground<C: View>(@ViewBuilder content: () -> C) -> some View {
        content()
            .padding(14)
            .background(Color.white.opacity(0.06))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Executing Card

    private func executingCard(_ item: TaskQueueItem) -> some View {
        cardBackground {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2).fill(Color.green).frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill").font(.system(size: 12)).foregroundColor(.green)
                        Text(item.title).font(.system(size: 15, weight: .medium)).foregroundColor(.white)
                    }
                    HStack(spacing: 6) {
                        if let a = item.assignedAgentName ?? item.assignedAgentId { Text(a) }
                        if let e = item.elapsedSeconds { Text("·"); Text(formatElapsed(e)) }
                        if let p = item.progress { Text("·"); Text("\(Int(p * 100))%").foregroundColor(.green) }
                    }.font(.system(size: 13)).foregroundColor(.gray)
                }
                Spacer()
            }
        }
    }

    // MARK: - Queued Card

    private func queuedCard(_ item: TaskQueueItem, index: Int) -> some View {
        cardBackground {
            HStack(spacing: 12) {
                Text("\(index)").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                    .frame(width: 28, height: 28).background(Color.blue).cornerRadius(8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.system(size: 15, weight: .medium)).foregroundColor(.white)
                    HStack(spacing: 4) {
                        Text("Priority: \(item.priority.rawValue.capitalized)")
                        Text("·")
                        Text("Source: \(item.source.rawValue.capitalized)")
                    }.font(.system(size: 13)).foregroundColor(.gray)
                }
                Spacer()
                HStack(spacing: 8) {
                    actionButton("chevron.up") { onMoveUp(item.id) }
                    actionButton("chevron.down") { onMoveDown(item.id) }
                    actionButton("xmark") { onCancel(item.id) }
                }
            }
        }
    }

    // MARK: - Completed Card

    private func completedCard(_ item: TaskQueueItem) -> some View {
        cardBackground {
            HStack(spacing: 12) {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundColor(.green)
                    .frame(width: 28, height: 28).background(Color.green.opacity(0.15)).cornerRadius(8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.system(size: 15, weight: .medium)).foregroundColor(.white)
                    HStack(spacing: 4) {
                        if let a = item.assignedAgentName ?? item.assignedAgentId { Text(a) }
                        if let d = item.completedAt { Text("·"); Text("Completed \(relativeTime(d))") }
                    }.font(.system(size: 13)).foregroundColor(.gray)
                }
                Spacer()
            }
        }.opacity(0.5)
    }

    // MARK: - Dispatch Bar

    private var dispatchBar: some View {
        HStack(spacing: 10) {
            TextField("Add a task…", text: $newTaskText)
                .textFieldStyle(.plain).padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.white.opacity(0.08)).cornerRadius(10).foregroundColor(.white)
            Button {
                let t = newTaskText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                onAddTask(t); newTaskText = ""
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 28))
                    .foregroundColor(newTaskText.isEmpty ? .gray : .blue)
            }.disabled(newTaskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).opacity(0.98))
    }

    // MARK: - Helpers

    private func actionButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundColor(.gray)
                .frame(width: 30, height: 30).background(Color.white.opacity(0.08)).cornerRadius(8)
        }
    }

    private func formatElapsed(_ seconds: Int) -> String {
        "\(seconds / 60)m\(String(format: "%02d", seconds % 60))s"
    }

    private func relativeTime(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }
}
