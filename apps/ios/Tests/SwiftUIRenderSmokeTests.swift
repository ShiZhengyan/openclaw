import OpenClawKit
import SwiftUI
import Testing
import UIKit
@testable import OpenClaw

@Suite struct SwiftUIRenderSmokeTests {
    @MainActor private static func host(_ view: some View) -> UIWindow {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        return window
    }

    @Test @MainActor func statusPillConnectingBuildsAViewHierarchy() {
        let root = StatusPill(gateway: .connecting, voiceWakeEnabled: true, brighten: true) {}
        _ = Self.host(root)
    }

    @Test @MainActor func statusPillDisconnectedBuildsAViewHierarchy() {
        let root = StatusPill(gateway: .disconnected, voiceWakeEnabled: false) {}
        _ = Self.host(root)
    }

    @Test @MainActor func settingsTabBuildsAViewHierarchy() {
        let appModel = NodeAppModel()
        let gatewayController = GatewayConnectionController(appModel: appModel, startDiscovery: false)

        let root = SettingsTab()
            .environment(appModel)
            .environment(appModel.voiceWake)
            .environment(gatewayController)

        _ = Self.host(root)
    }

    @Test @MainActor func rootTabsBuildAViewHierarchy() {
        let appModel = NodeAppModel()
        let gatewayController = GatewayConnectionController(appModel: appModel, startDiscovery: false)

        let root = RootTabs()
            .environment(appModel)
            .environment(appModel.voiceWake)
            .environment(gatewayController)

        _ = Self.host(root)
    }

    @Test @MainActor func voiceTabBuildsAViewHierarchy() {
        let appModel = NodeAppModel()

        let root = VoiceTab()
            .environment(appModel)
            .environment(appModel.voiceWake)

        _ = Self.host(root)
    }

    @Test @MainActor func voiceWakeWordsViewBuildsAViewHierarchy() {
        let appModel = NodeAppModel()
        let root = NavigationStack { VoiceWakeWordsSettingsView() }
            .environment(appModel)
        _ = Self.host(root)
    }

    @Test @MainActor func chatSheetBuildsAViewHierarchy() {
        let appModel = NodeAppModel()
        let gateway = GatewayNodeSession()
        let root = ChatSheet(gateway: gateway, sessionKey: "test")
            .environment(appModel)
            .environment(appModel.voiceWake)
        _ = Self.host(root)
    }

    @Test @MainActor func voiceWakeToastBuildsAViewHierarchy() {
        let root = VoiceWakeToast(command: "openclaw: do something")
        _ = Self.host(root)
    }

    // MARK: - Dashboard Views

    @Test @MainActor func dashboardTabBuildsAViewHierarchy() {
        let appModel = NodeAppModel()
        let dashboard = DashboardController()
        let root = DashboardTab()
            .environment(appModel)
            .environment(dashboard)
        _ = Self.host(root)
    }

    @Test @MainActor func dashboardRootViewBuildsAViewHierarchy() {
        let appModel = NodeAppModel()
        let gatewayController = GatewayConnectionController(appModel: appModel, startDiscovery: false)
        let root = DashboardRootView()
            .environment(appModel)
            .environment(appModel.voiceWake)
            .environment(gatewayController)
        _ = Self.host(root)
    }

    @Test @MainActor func summaryBarBuildsAViewHierarchy() {
        let root = SummaryBar(summary: DashboardSummary(running: 3, idle: 1, error: 1, queued: 4))
        _ = Self.host(root)
    }

    @Test @MainActor func agentCardRunningBuildsAViewHierarchy() {
        let agent = AgentRunInfo(
            id: "test", name: "test-agent", status: .running,
            currentTask: "Some task", elapsedSeconds: 60, progress: 0.5,
            lastToolCall: "edit file.ts")
        let root = AgentCardView(agent: agent)
        _ = Self.host(root)
    }

    @Test @MainActor func agentCardErrorBuildsAViewHierarchy() {
        let agent = AgentRunInfo(
            id: "test", name: "test-agent", status: .error,
            currentTask: "Failed task", errorMessage: "Something went wrong")
        let root = AgentCardView(agent: agent)
        _ = Self.host(root)
    }

    @Test @MainActor func agentCardIdleBuildsAViewHierarchy() {
        let agent = AgentRunInfo(id: "test", name: "test-agent", status: .idle)
        let root = AgentCardView(agent: agent)
        _ = Self.host(root)
    }

    @Test @MainActor func agentCardPlanReviewBuildsAViewHierarchy() {
        let agent = AgentRunInfo(
            id: "test", name: "test-agent", status: .planReview,
            currentTask: "Migration plan", planContent: "## Goal\nMigrate DB")
        let root = AgentCardView(agent: agent)
        _ = Self.host(root)
    }

    @Test @MainActor func agentDetailViewBuildsAViewHierarchy() {
        let appModel = NodeAppModel()
        let dashboard = DashboardController()
        let agent = AgentRunInfo(
            id: "test", name: "test-agent", status: .running,
            currentTask: "Some task", elapsedSeconds: 120, progress: 0.7)
        let root = NavigationStack { AgentDetailView(agent: agent) }
            .environment(appModel)
            .environment(dashboard)
        _ = Self.host(root)
    }

    @Test @MainActor func agentEventTimelineBuildsAViewHierarchy() {
        let events: [AgentToolEvent] = [
            AgentToolEvent(id: "1", kind: .thinking, title: "Thinking...", detail: nil,
                           codeSnippet: nil, timestamp: Date(), isInProgress: true),
            AgentToolEvent(id: "2", kind: .editFile, title: "Edit: file.ts", detail: "Changed line",
                           codeSnippet: "- old\n+ new", timestamp: Date(), isInProgress: false),
        ]
        let root = AgentEventTimeline(events: events)
        _ = Self.host(root)
    }

    @Test @MainActor func taskDispatchBarBuildsAViewHierarchy() {
        let root = TaskDispatchBar(
            text: .constant("test"), isRecording: false,
            onSubmit: { _ in }, onQuickLaunch: { _ in }, onMicTap: {},
            onQuickAction: { _ in }, onQuickActionLongPress: { _ in })
        _ = Self.host(root)
    }

    @Test @MainActor func taskDispatchSheetBuildsAViewHierarchy() {
        let agents = [AgentRunInfo(id: "test", name: "test-agent", status: .idle)]
        let root = TaskDispatchSheet(
            options: .constant(TaskDispatchOptions(message: "test task")),
            agents: agents, recentDirectories: ["~/project"],
            onLaunch: {}, onCancel: {})
        _ = Self.host(root)
    }

    @Test @MainActor func planReviewSheetBuildsAViewHierarchy() {
        let root = PlanReviewSheet(
            agentName: "reviewer", planContent: "## Goal\nTest plan",
            onApprove: { _ in }, onReject: { _ in })
        _ = Self.host(root)
    }

    @Test @MainActor func taskQueueViewBuildsAViewHierarchy() {
        let items = [
            TaskQueueItem(id: "1", title: "Test task", priority: .high, source: .manual, status: .queued),
        ]
        let root = NavigationStack { TaskQueueView(items: items) }
        _ = Self.host(root)
    }

    @Test @MainActor func quickActionsBarBuildsAViewHierarchy() {
        let root = QuickActionsBar(onQuickAction: { _ in }, onQuickActionLongPress: { _ in })
        _ = Self.host(root)
    }

    @Test @MainActor func directoryPickerSheetBuildsAViewHierarchy() {
        let root = DirectoryPickerSheet(
            recentDirectories: ["~/project", "~/api"],
            selectedDirectory: .constant("~/project"),
            onDone: {})
        _ = Self.host(root)
    }
}
