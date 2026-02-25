import Foundation

// MARK: - Thinking Level

enum ThinkingLevel: String, CaseIterable, Sendable {
    case off
    case low
    case medium = "med"
    case high

    var displayLabel: String {
        switch self {
        case .off: "Off"
        case .low: "Low"
        case .medium: "Med"
        case .high: "High"
        }
    }

    /// Value sent to the gateway `thinking` parameter.
    var apiValue: String { rawValue == "med" ? "medium" : rawValue }
}

// MARK: - Session Mode

enum SessionMode: Sendable {
    case new
    case continueExisting(sessionKey: String, label: String?)
}

// MARK: - Task Dispatch Options

/// Full set of options for dispatching a task via the gateway `agent` method.
struct TaskDispatchOptions: Sendable {
    var message: String
    var agentId: String?              // nil = auto (first idle)
    var workingDirectory: String?     // nil = agent default
    var thinking: ThinkingLevel = .low
    var sessionMode: SessionMode = .new
    var label: String?                // auto-prefilled from message
    var model: String?                // nil = agent default
    var timeout: Int = 300            // seconds (5 min default)
    var extraContext: String?         // extra system prompt
    var source: TaskInputSource = .manual
}

// MARK: - Task Input Source

enum TaskInputSource: String, Sendable {
    case manual
    case voice
    case quickAction
}

// MARK: - Quick Action

enum QuickAction: String, CaseIterable, Sendable, Identifiable {
    case runTests
    case fixLint
    case continueTask
    case reviewCode
    case refactor

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .runTests: "🧪"
        case .fixLint: "🔧"
        case .continueTask: "📝"
        case .reviewCode: "🔍"
        case .refactor: "🧹"
        }
    }

    var label: String {
        switch self {
        case .runTests: "Tests"
        case .fixLint: "Lint"
        case .continueTask: "Continue"
        case .reviewCode: "Review"
        case .refactor: "Refactor"
        }
    }

    var message: String {
        switch self {
        case .runTests: "Run the test suite and fix any failures"
        case .fixLint: "Fix all linting errors and warnings"
        case .continueTask: "Continue where you left off"
        case .reviewCode: "Review recent changes for bugs and issues"
        case .refactor: "Refactor for clarity and maintainability"
        }
    }

    var thinking: ThinkingLevel {
        switch self {
        case .runTests: .low
        case .fixLint: .off
        case .continueTask: .low
        case .reviewCode: .high
        case .refactor: .medium
        }
    }

    /// Build dispatch options from this quick action.
    func toOptions() -> TaskDispatchOptions {
        TaskDispatchOptions(
            message: message,
            thinking: thinking,
            source: .quickAction)
    }
}

// MARK: - Timeout Presets

enum TimeoutPreset: Int, CaseIterable, Sendable, Identifiable {
    case fiveMin = 300
    case fifteenMin = 900
    case thirtyMin = 1800
    case oneHour = 3600
    case unlimited = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .fiveMin: "5m"
        case .fifteenMin: "15m"
        case .thirtyMin: "30m"
        case .oneHour: "1h"
        case .unlimited: "∞"
        }
    }
}
