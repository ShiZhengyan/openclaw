import Foundation

// MARK: - Agent Status

enum AgentStatus: String, Sendable {
    case running
    case idle
    case error
    case planReview // waiting for plan approval
}

// MARK: - Agent Run Info

/// Tracks the live state of a single agent, combining static metadata from `agents.list`
/// with runtime status derived from agent events.
struct AgentRunInfo: Identifiable, Hashable, Sendable {
    static func == (lhs: AgentRunInfo, rhs: AgentRunInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id: String // agent ID
    let name: String // display name
    var status: AgentStatus
    var currentTask: String? // description of current task
    var elapsedSeconds: Int? // how long current task has been running
    var progress: Double? // 0.0-1.0 estimated progress (nil if unknown)
    var lastToolCall: String? // e.g. "edit src/auth.ts"
    var errorMessage: String? // truncated error when status == .error
    var planContent: String? // markdown plan when status == .planReview
    var runId: String? // current run ID
    var sessionKey: String? // session key for this agent
    var emoji: String? // agent emoji from identity

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? id : name
    }
}

// MARK: - Agent Tool Event

/// A single event in the agent's tool call timeline (for the detail view).
struct AgentToolEvent: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case thinking
        case readFile
        case editFile
        case bash
        case search
        case other
    }

    let id: String // unique event ID (runId-seq)
    let kind: Kind
    let title: String // e.g. "Read: src/auth.ts"
    let detail: String? // secondary info
    let codeSnippet: String? // diff or output preview
    let timestamp: Date
    var isInProgress: Bool
}

// MARK: - Task Queue Item

struct TaskQueueItem: Identifiable, Sendable {
    enum Source: String, Sendable {
        case voice
        case manual
        case cron
    }

    enum Priority: String, Sendable, Comparable {
        case high
        case medium
        case low

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            let order: [Priority] = [.low, .medium, .high]
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }

    enum Status: String, Sendable {
        case queued
        case executing
        case completed
        case failed
    }

    let id: String
    var title: String
    var priority: Priority
    var source: Source
    var status: Status
    var assignedAgentId: String?
    var assignedAgentName: String?
    var elapsedSeconds: Int?
    var progress: Double?
    var completedAt: Date?
    var error: String?
}

// MARK: - Dashboard Summary

/// Snapshot of counts for the summary bar.
struct DashboardSummary: Sendable {
    var running: Int = 0
    var idle: Int = 0
    var error: Int = 0
    var queued: Int = 0
}
