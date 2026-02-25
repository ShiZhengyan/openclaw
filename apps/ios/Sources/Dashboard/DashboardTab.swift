import OpenClawKit
import SwiftUI

struct DashboardTab: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(DashboardController.self) private var dashboard

    @State private var dispatchText: String = ""
    @State private var showTaskQueue: Bool = false
    @State private var selectedAgentForPlan: AgentRunInfo?
    @State private var selectedAgentForDetail: AgentRunInfo?
    @State private var showDispatchSheet: Bool = false
    @State private var dispatchOptions = TaskDispatchOptions(message: "")

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal)
                    .padding(.top, 8)

                SummaryBar(summary: dashboard.summary) { status in
                    if status == nil && dashboard.selectedFilter == nil {
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        dashboard.selectedFilter = dashboard.selectedFilter == status ? nil : status
                    }
                }
                .overlay(alignment: .trailing) {
                    Color.clear
                        .frame(width: 80, height: 60)
                        .contentShape(Rectangle())
                        .onTapGesture { showTaskQueue = true }
                        .offset(x: -8)
                }
                .padding(.horizontal)
                .padding(.top, 12)

                agentList
                    .padding(.top, 8)

                TaskDispatchBar(
                    text: $dispatchText,
                    isRecording: false,
                    onSubmit: { message in
                        // Tap send → open dispatch sheet
                        dispatchOptions = TaskDispatchOptions(message: message, source: .manual)
                        dispatchOptions.label = String(message.prefix(40))
                        showDispatchSheet = true
                    },
                    onQuickLaunch: { message in
                        // Long-press send → dispatch immediately with defaults
                        Task {
                            await dashboard.dispatchTask(
                                options: TaskDispatchOptions(message: message),
                                appModel: appModel)
                        }
                        dispatchText = ""
                    },
                    onMicTap: {},
                    onQuickAction: { action in
                        // Quick action tap → instant dispatch
                        Task {
                            await dashboard.dispatchTask(
                                options: action.toOptions(),
                                appModel: appModel)
                        }
                    },
                    onQuickActionLongPress: { action in
                        // Quick action long-press → open sheet pre-filled
                        dispatchOptions = action.toOptions()
                        dispatchOptions.label = action.label
                        showDispatchSheet = true
                    })
                .padding(.bottom, 8)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationDestination(item: $selectedAgentForDetail) { agent in
                AgentDetailView(agent: agent)
            }
            .navigationDestination(isPresented: $showTaskQueue) {
                TaskQueueView(items: dashboard.taskQueue)
            }
            .sheet(item: $selectedAgentForPlan) { agent in
                PlanReviewSheet(
                    agentName: agent.displayName,
                    planContent: agent.planContent ?? "",
                    onApprove: { note in
                        Task {
                            await dashboard.approvePlan(agent.id, note: note, appModel: appModel)
                        }
                        selectedAgentForPlan = nil
                    },
                    onReject: { note in
                        Task {
                            await dashboard.rejectPlan(agent.id, note: note, appModel: appModel)
                        }
                        selectedAgentForPlan = nil
                    })
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showDispatchSheet) {
                TaskDispatchSheet(
                    options: $dispatchOptions,
                    agents: dashboard.agents,
                    recentDirectories: dashboard.recentDirectories,
                    onLaunch: {
                        showDispatchSheet = false
                        Task {
                            await dashboard.dispatchTask(
                                options: dispatchOptions,
                                appModel: appModel)
                        }
                        dispatchText = ""
                    },
                    onCancel: {
                        showDispatchSheet = false
                    })
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
            }
            .task {
                dashboard.startMonitoring(appModel: appModel)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Dashboard")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            let total = dashboard.agents.count
            let online = dashboard.summary.running
            Text("\(total) agents · \(online) 🟢")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Agent List

    private var agentList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(dashboard.filteredAgents) { agent in
                    AgentCardView(
                        agent: agent,
                        onTap: { selectedAgentForDetail = agent },
                        onRetry: {
                            Task { await dashboard.retryAgent(agent.id, appModel: appModel) }
                        },
                        onDispatch: {
                            dispatchOptions = TaskDispatchOptions(message: "", agentId: agent.id)
                            showDispatchSheet = true
                        },
                        onViewPlan: { selectedAgentForPlan = agent },
                        onApprovePlan: {
                            Task {
                                await dashboard.approvePlan(agent.id, note: nil, appModel: appModel)
                            }
                        },
                        onRejectPlan: {
                            Task {
                                await dashboard.rejectPlan(agent.id, note: nil, appModel: appModel)
                            }
                        })
                }
            }
            .padding(.horizontal)
        }
    }
}
