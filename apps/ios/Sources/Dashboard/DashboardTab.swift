import OpenClawKit
import SwiftUI

struct DashboardTab: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(DashboardController.self) private var dashboard

    @State private var dispatchText: String = ""
    @State private var showTaskQueue: Bool = false
    @State private var selectedAgentForPlan: AgentRunInfo?
    @State private var selectedAgentForDetail: AgentRunInfo?

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
                    if let status, status == .idle, dashboard.selectedFilter == .idle {
                        // Tapping "queued" navigates to TaskQueueView
                    }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        dashboard.selectedFilter = dashboard.selectedFilter == status ? nil : status
                    }
                }
                .onTapGesture {} // consumed by SummaryBar
                .overlay(alignment: .trailing) {
                    // Invisible tap target over the "Queue" stat to navigate
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
                        Task {
                            await dashboard.dispatchTask(
                                message: message, agentId: nil, appModel: appModel
                            )
                        }
                        dispatchText = ""
                    },
                    onMicTap: {}
                )
                .padding(.horizontal)
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
                    }
                )
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
                            dispatchText = "@\(agent.name) "
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
                        }
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}
