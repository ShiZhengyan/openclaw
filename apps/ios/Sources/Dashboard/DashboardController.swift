import Foundation
import Observation
import OpenClawKit
import OpenClawProtocol
import OpenClawChatUI
import os

@MainActor
@Observable
final class DashboardController {
    private let logger = Logger(subsystem: "ai.openclaw.ios", category: "Dashboard")

    // Published state
    var agents: [AgentRunInfo] = []
    var taskQueue: [TaskQueueItem] = []
    var selectedFilter: AgentStatus? = nil
    var isLoading: Bool = false
    var recentDirectories: [String] = ["~/projects/my-app", "~/projects/api", "~/web"]
    /// Last-used dispatch options per agent ID.
    private var lastUsedOptions: [String: TaskDispatchOptions] = [:]

    // Event subscription
    private var eventSubscriptionTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var agentTimerTask: Task<Void, Never>?
    // Track agent run start times for elapsed calculation
    private var runStartTimes: [String: Date] = [:]

    // Computed
    var summary: DashboardSummary {
        var s = DashboardSummary()
        for agent in agents {
            switch agent.status {
            case .running: s.running += 1
            case .idle: s.idle += 1
            case .error: s.error += 1
            case .planReview: s.running += 1
            }
        }
        s.queued = taskQueue.filter { $0.status == .queued }.count
        return s
    }

    var filteredAgents: [AgentRunInfo] {
        guard let filter = selectedFilter else { return agents }
        return agents.filter { $0.status == filter }
    }

    // MARK: - Lifecycle

    func startMonitoring(appModel: NodeAppModel) {
        stopMonitoring()

        // Initial load — try gateway first, fall back to mock data quickly
        refreshTask = Task {
            // If no gateway connection, load mock data immediately
            if appModel.gatewayServerName == nil {
                self.loadMockAgents()
            }
            await loadAgents(appModel: appModel)
        }

        // Subscribe to agent events
        eventSubscriptionTask = Task {
            let session = appModel.operatorSession
            let stream = await session.subscribeServerEvents(bufferingNewest: 200)
            for await event in stream {
                if Task.isCancelled { return }
                guard event.event == "agent" else { continue }
                guard let payload = event.payload else { continue }
                do {
                    let agentEvent = try GatewayPayloadDecoding.decode(
                        payload, as: OpenClawAgentEventPayload.self)
                    await MainActor.run {
                        self.handleAgentEvent(agentEvent)
                    }
                } catch {
                    logger.debug("Failed to decode agent event: \(error.localizedDescription)")
                }
            }
        }

        // Timer to update elapsed times every second
        agentTimerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    self.updateElapsedTimes()
                }
            }
        }
    }

    func stopMonitoring() {
        eventSubscriptionTask?.cancel()
        eventSubscriptionTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        agentTimerTask?.cancel()
        agentTimerTask = nil
    }

    // MARK: - API Calls

    func loadAgents(appModel: NodeAppModel) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let session = appModel.operatorSession
            let res = try await session.request(method: "agents.list", paramsJSON: "{}", timeoutSeconds: 8)
            let decoded = try JSONDecoder().decode(AgentsListResult.self, from: res)

            // Merge with existing runtime state
            var updatedAgents: [AgentRunInfo] = []
            for summary in decoded.agents {
                if let existing = agents.first(where: { $0.id == summary.id }) {
                    updatedAgents.append(existing)
                } else {
                    let name = (summary.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let emoji = extractEmoji(from: summary.identity)
                    updatedAgents.append(AgentRunInfo(
                        id: summary.id,
                        name: name.isEmpty ? summary.id : name,
                        status: .idle,
                        emoji: emoji))
                }
            }
            agents = updatedAgents
        } catch {
            logger.error("Failed to load agents: \(error.localizedDescription)")
        }
    }

    func dispatchTask(options: TaskDispatchOptions, appModel: NodeAppModel) async {
        let targetAgent = options.agentId ?? agents.first(where: { $0.status == .idle })?.id

        guard let resolvedAgent = targetAgent else {
            // No idle agent available — queue the task
            let item = TaskQueueItem(
                id: UUID().uuidString,
                title: options.message,
                priority: .medium,
                source: options.source == .voice ? .voice : .manual,
                status: .queued)
            taskQueue.append(item)
            return
        }

        // Persist last-used options for this agent
        lastUsedOptions[resolvedAgent] = options

        // Update recent directories
        if let dir = options.workingDirectory,
           !dir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            recentDirectories.removeAll { $0 == dir }
            recentDirectories.insert(dir, at: 0)
            if recentDirectories.count > 8 { recentDirectories = Array(recentDirectories.prefix(8)) }
        }

        // Mark agent as running
        if let idx = agents.firstIndex(where: { $0.id == resolvedAgent }) {
            agents[idx].status = .running
            agents[idx].currentTask = options.message
            agents[idx].progress = nil
            agents[idx].elapsedSeconds = 0
        }

        do {
            let session = appModel.operatorSession
            struct AgentParams: Codable {
                var message: String
                var agentId: String?
                var thinking: String?
                var label: String?
                var timeout: Int?
                var extraSystemPrompt: String?
                var idempotencyKey: String
                var timeoutMs: Int = 300_000
            }
            let thinkingValue = options.thinking != .low ? options.thinking.apiValue : nil
            let params = AgentParams(
                message: options.message,
                agentId: resolvedAgent,
                thinking: thinkingValue,
                label: options.label,
                timeout: options.timeout > 0 ? options.timeout : nil,
                extraSystemPrompt: options.extraContext,
                idempotencyKey: UUID().uuidString,
                timeoutMs: options.timeout > 0 ? options.timeout * 1000 : 300_000)
            let data = try JSONEncoder().encode(params)
            let json = String(data: data, encoding: .utf8)
            _ = try await session.request(method: "agent", paramsJSON: json, timeoutSeconds: 10)
        } catch {
            logger.error("Failed to dispatch task: \(error.localizedDescription)")
            if let idx = agents.firstIndex(where: { $0.id == resolvedAgent }) {
                agents[idx].status = .error
                agents[idx].errorMessage = error.localizedDescription
            }
        }
    }

    /// Legacy convenience for simple dispatch calls.
    func dispatchTask(message: String, agentId: String?, appModel: NodeAppModel) async {
        await dispatchTask(
            options: TaskDispatchOptions(message: message, agentId: agentId),
            appModel: appModel)
    }

    func retryAgent(_ agentId: String, appModel: NodeAppModel) async {
        guard let idx = agents.firstIndex(where: { $0.id == agentId }),
              let lastTask = agents[idx].currentTask else { return }
        agents[idx].status = .idle
        agents[idx].errorMessage = nil
        await dispatchTask(message: lastTask, agentId: agentId, appModel: appModel)
    }

    func approvePlan(_ agentId: String, note: String?, appModel: NodeAppModel) async {
        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            agents[idx].status = .running
            agents[idx].planContent = nil
        }
        let message = note?.isEmpty == false ? "Approved. Note: \(note!)" : "Approved. Proceed with the plan."
        await dispatchTask(message: message, agentId: agentId, appModel: appModel)
    }

    func rejectPlan(_ agentId: String, note: String?, appModel: NodeAppModel) async {
        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            agents[idx].status = .running
            agents[idx].planContent = nil
        }
        let message = note?.isEmpty == false ? "Plan rejected. Feedback: \(note!)" : "Plan rejected. Please revise."
        await dispatchTask(message: message, agentId: agentId, appModel: appModel)
    }

    // MARK: - Event Handling

    private func handleAgentEvent(_ event: OpenClawAgentEventPayload) {
        let runId = event.runId
        let stream = event.stream
        let data = event.data

        switch stream {
        case "lifecycle":
            handleLifecycleEvent(runId: runId, data: data)
        case "tool":
            handleToolEvent(runId: runId, data: data)
        case "assistant":
            break
        case "error":
            handleErrorEvent(runId: runId, data: data)
        default:
            break
        }
    }

    private func handleLifecycleEvent(runId: String, data: [String: AnyCodable]) {
        let phase = (data["phase"]?.value as? String) ?? ""
        let agentId = (data["agentId"]?.value as? String) ?? ""
        let label = (data["label"]?.value as? String)

        switch phase {
        case "start":
            runStartTimes[runId] = Date()
            if let idx = agents.firstIndex(where: { $0.id == agentId || $0.runId == runId }) {
                agents[idx].status = .running
                agents[idx].runId = runId
                agents[idx].elapsedSeconds = 0
                if let label { agents[idx].currentTask = label }
            }
        case "end":
            runStartTimes.removeValue(forKey: runId)
            if let idx = agents.firstIndex(where: { $0.runId == runId }) {
                agents[idx].status = .idle
                agents[idx].progress = nil
                agents[idx].lastToolCall = nil
                agents[idx].elapsedSeconds = nil
                agents[idx].runId = nil
            }
        case "error":
            runStartTimes.removeValue(forKey: runId)
            let errorMsg = (data["error"]?.value as? String) ?? "Unknown error"
            if let idx = agents.firstIndex(where: { $0.runId == runId }) {
                agents[idx].status = .error
                agents[idx].errorMessage = String(errorMsg.prefix(200))
            }
        default:
            break
        }
    }

    private func handleToolEvent(runId: String, data: [String: AnyCodable]) {
        let tool = (data["tool"]?.value as? String) ?? ""
        let toolInput = data["input"]?.value

        guard let idx = agents.firstIndex(where: { $0.runId == runId }) else { return }

        var toolDisplay = tool
        if let inputDict = toolInput as? [String: Any],
           let path = inputDict["path"] as? String {
            toolDisplay = "\(tool) \(path)"
        }
        agents[idx].lastToolCall = toolDisplay
    }

    private func handleErrorEvent(runId: String, data: [String: AnyCodable]) {
        let errorMsg = (data["error"]?.value as? String) ?? "Unknown error"
        if let idx = agents.firstIndex(where: { $0.runId == runId }) {
            agents[idx].status = .error
            agents[idx].errorMessage = String(errorMsg.prefix(200))
        }
    }

    private func updateElapsedTimes() {
        let now = Date()
        for i in agents.indices where agents[i].status == .running {
            if let runId = agents[i].runId, let start = runStartTimes[runId] {
                agents[i].elapsedSeconds = Int(now.timeIntervalSince(start))
            }
        }
    }

    // MARK: - Helpers

    private func extractEmoji(from identity: [String: AnyCodable]?) -> String? {
        guard let identity else { return nil }
        return identity["emoji"]?.value as? String
    }

    func formatElapsed(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let secs = seconds % 60
        return secs > 0 ? "\(minutes)m\(secs)s" : "\(minutes)m"
    }

    // MARK: - Mock Data (for development without gateway)

    private func loadMockAgents() {
        agents = [
            AgentRunInfo(
                id: "ralph", name: "ralph", status: .running,
                currentTask: "Refactoring auth module",
                elapsedSeconds: 263, progress: 0.72,
                lastToolCall: "edit src/auth.ts",
                runId: "run-1", emoji: "🔧",
                workspace: "~/projects/my-app"),
            AgentRunInfo(
                id: "builder", name: "builder", status: .running,
                currentTask: "Fixing CI pipeline",
                elapsedSeconds: 720, progress: 0.35,
                lastToolCall: "bash: npm test",
                runId: "run-2", emoji: "🏗",
                workspace: "~/projects/api"),
            AgentRunInfo(
                id: "docs-writer", name: "docs-writer", status: .error,
                currentTask: "API docs generation failed",
                errorMessage: "TypeDoc parse error at models/user.ts:42",
                emoji: "📝",
                workspace: "~/projects/api"),
            AgentRunInfo(
                id: "reviewer", name: "reviewer", status: .planReview,
                currentTask: "Database migration plan",
                planContent: "## Goal\nMigrate user table from SQLite to PostgreSQL\n\n## Steps\n1. Create PostgreSQL schema\n2. Write migration script\n3. Update ORM config\n4. Add connection pool\n5. Run tests\n\n## Impact\n- Modify 5 files\n- Add 2 files",
                emoji: "🔍",
                workspace: "~/projects/my-app"),
            AgentRunInfo(
                id: "analyst", name: "analyst", status: .idle,
                emoji: "📊",
                workspace: "~/projects/my-app"),
        ]
        runStartTimes["run-1"] = Date().addingTimeInterval(-263)
        runStartTimes["run-2"] = Date().addingTimeInterval(-720)
        taskQueue = [
            TaskQueueItem(id: "q1", title: "Write user registration feature", priority: .high, source: .voice, status: .queued),
            TaskQueueItem(id: "q2", title: "Add README install instructions", priority: .medium, source: .manual, status: .queued),
            TaskQueueItem(id: "q3", title: "Fix linter warnings", priority: .low, source: .cron, status: .queued),
        ]
    }
}
