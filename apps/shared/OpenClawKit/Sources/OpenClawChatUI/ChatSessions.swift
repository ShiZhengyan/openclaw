import Foundation

public struct OpenClawChatSessionsDefaults: Codable, Sendable {
    public let model: String?
    public let contextTokens: Int?
}

public struct OpenClawChatSessionEntry: Codable, Identifiable, Sendable, Hashable {
    public var id: String { self.key }

    public let key: String
    public let kind: String?
    public let displayName: String?
    public let surface: String?
    public let subject: String?
    public let room: String?
    public let space: String?
    public let updatedAt: Double?
    public let sessionId: String?

    public let systemSent: Bool?
    public let abortedLastRun: Bool?
    public let thinkingLevel: String?
    public let verboseLevel: String?

    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?

    public let model: String?
    public let contextTokens: Int?
}

public struct OpenClawChatSessionsListResponse: Codable, Sendable {
    public let ts: Double?
    public let path: String?
    public let count: Int?
    public let defaults: OpenClawChatSessionsDefaults?
    public let sessions: [OpenClawChatSessionEntry]
}

// MARK: - Friendly Session Name Formatting

extension OpenClawChatSessionEntry {
    /// Returns a human-readable name for the session, preferring `displayName` and
    /// falling back to a cleaned-up version of the raw key.
    public var friendlyName: String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }
        return Self.formatSessionKey(self.key)
    }

    /// Converts raw session keys like "agent:main:main" into readable labels.
    public static func formatSessionKey(_ key: String) -> String {
        var name = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Untitled" }

        // Strip common prefixes: "agent:main:", "agent:", "session:"
        for prefix in ["agent:main:", "agent:", "session:"] {
            if name.lowercased().hasPrefix(prefix) {
                name = String(name.dropFirst(prefix.count))
                break
            }
        }

        // Replace separators with spaces
        name = name.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ":", with: " ")

        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Untitled" }

        // Capitalize first letter
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Relative timestamp for display (e.g. "2h ago", "Yesterday").
    public var relativeTimestamp: String? {
        guard let updatedAt, updatedAt > 0 else { return nil }
        let date = Date(timeIntervalSince1970: updatedAt / 1000)
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 172_800 { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
