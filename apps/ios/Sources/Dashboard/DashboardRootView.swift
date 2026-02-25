import OpenClawKit
import SwiftUI
import UIKit

struct DashboardRootView: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(GatewayConnectionController.self) private var gatewayController
    @Environment(VoiceWakeManager.self) private var voiceWake
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(VoiceWakePreferences.enabledKey) private var voiceWakeEnabled: Bool = false
    @AppStorage("screen.preventSleep") private var preventSleep: Bool = true
    @AppStorage("onboarding.requestID") private var onboardingRequestID: Int = 0
    @AppStorage("gateway.onboardingComplete") private var onboardingComplete: Bool = false
    @AppStorage("gateway.hasConnectedOnce") private var hasConnectedOnce: Bool = false
    @AppStorage("gateway.preferredStableID") private var preferredGatewayStableID: String = ""
    @AppStorage("gateway.manual.enabled") private var manualGatewayEnabled: Bool = false
    @AppStorage("gateway.manual.host") private var manualGatewayHost: String = ""
    @AppStorage("onboarding.quickSetupDismissed") private var quickSetupDismissed: Bool = false

    @State private var dashboard = DashboardController()
    @State private var selectedTab: Int = 0
    @State private var voiceWakeToastText: String?
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var showOnboarding: Bool = false
    @State private var onboardingAllowSkip: Bool = true
    @State private var didEvaluateOnboarding: Bool = false
    @State private var didAutoOpenSettings: Bool = false
    @State private var showQuickSetup: Bool = false
    @State private var showGatewayActions: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: self.$selectedTab) {
                DashboardTab()
                    .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
                    .tag(0)

                self.chatTab
                    .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                    .tag(1)

                SettingsTab()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(2)
            }
            .environment(self.dashboard)

            if self.appModel.cameraFlashNonce != 0 {
                CameraFlashOverlay(nonce: self.appModel.cameraFlashNonce)
            }
        }
        .preferredColorScheme(.dark)
        // Status pill overlay
        .overlay(alignment: .topLeading) {
            StatusPill(
                gateway: self.gatewayStatus,
                voiceWakeEnabled: self.voiceWakeEnabled,
                activity: self.statusActivity,
                onTap: {
                    if self.gatewayStatus == .connected {
                        self.showGatewayActions = true
                    } else {
                        self.selectedTab = 2
                    }
                })
                .padding(.leading, 10)
                .safeAreaPadding(.top, 10)
        }
        // Voice wake toast
        .overlay(alignment: .topLeading) {
            if let voiceWakeToastText, !voiceWakeToastText.isEmpty {
                VoiceWakeToast(command: voiceWakeToastText)
                    .padding(.leading, 10)
                    .safeAreaPadding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        // Talk orb overlay
        .overlay(alignment: .center) {
            if self.appModel.talkMode.isEnabled {
                TalkOrbOverlay()
                    .transition(.opacity)
            }
        }
        // Gateway actions dialog
        .confirmationDialog(
            "Gateway",
            isPresented: self.$showGatewayActions,
            titleVisibility: .visible)
        {
            Button("Disconnect", role: .destructive) {
                self.appModel.disconnectGateway()
            }
            Button("Open Settings") {
                self.selectedTab = 2
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Disconnect from the gateway?")
        }
        // Trust prompt
        .gatewayTrustPromptAlert()
        // Quick setup sheet
        .sheet(isPresented: self.$showQuickSetup) {
            GatewayQuickSetupSheet()
                .environment(self.appModel)
                .environment(self.appModel.voiceWake)
                .environment(self.gatewayController)
        }
        // Onboarding full screen cover
        .fullScreenCover(isPresented: self.$showOnboarding) {
            OnboardingWizardView(
                allowSkip: self.onboardingAllowSkip,
                onClose: {
                    self.showOnboarding = false
                })
                .environment(self.appModel)
                .environment(self.appModel.voiceWake)
                .environment(self.gatewayController)
        }
        // Lifecycle handlers
        .onAppear { self.updateIdleTimer() }
        .onAppear { self.evaluateOnboardingPresentation(force: false) }
        .onAppear { self.maybeAutoOpenSettings() }
        .onAppear { self.maybeShowQuickSetup() }
        .onChange(of: self.preventSleep) { _, _ in self.updateIdleTimer() }
        .onChange(of: self.scenePhase) { _, _ in self.updateIdleTimer() }
        .onChange(of: self.gatewayController.gateways.count) { _, _ in self.maybeShowQuickSetup() }
        .onChange(of: self.appModel.gatewayServerName) { _, newValue in
            if newValue != nil {
                self.showOnboarding = false
                self.onboardingComplete = true
                self.hasConnectedOnce = true
                OnboardingStateStore.markCompleted(mode: nil)
            }
            self.maybeAutoOpenSettings()
        }
        .onChange(of: self.onboardingRequestID) { _, _ in
            self.evaluateOnboardingPresentation(force: true)
        }
        .onChange(of: self.appModel.openChatRequestID) { _, _ in
            self.selectedTab = 1
        }
        .onChange(of: self.voiceWake.lastTriggeredCommand) { _, newValue in
            guard let newValue else { return }
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            self.toastDismissTask?.cancel()
            withAnimation(self.reduceMotion ? .none : .spring(response: 0.25, dampingFraction: 0.85)) {
                self.voiceWakeToastText = trimmed
            }

            self.toastDismissTask = Task {
                try? await Task.sleep(nanoseconds: 2_300_000_000)
                await MainActor.run {
                    withAnimation(self.reduceMotion ? .none : .easeOut(duration: 0.25)) {
                        self.voiceWakeToastText = nil
                    }
                }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            self.toastDismissTask?.cancel()
            self.toastDismissTask = nil
        }
    }

    // MARK: - Chat Tab

    @ViewBuilder
    private var chatTab: some View {
        if self.appModel.gatewayServerName != nil {
            ChatSheet(
                gateway: self.appModel.operatorSession,
                sessionKey: self.appModel.chatSessionKey,
                agentName: self.appModel.activeAgentName,
                userAccent: self.appModel.seamColor)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Connect to a gateway to start chatting")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
    }

    // MARK: - Gateway Status

    private var gatewayStatus: StatusPill.GatewayState {
        if self.appModel.gatewayServerName != nil { return .connected }

        let text = self.appModel.gatewayStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.localizedCaseInsensitiveContains("connecting") ||
            text.localizedCaseInsensitiveContains("reconnecting")
        {
            return .connecting
        }

        if text.localizedCaseInsensitiveContains("error") {
            return .error
        }

        return .disconnected
    }

    private var statusActivity: StatusPill.Activity? {
        StatusActivityBuilder.build(
            appModel: self.appModel,
            voiceWakeEnabled: self.voiceWakeEnabled,
            cameraHUDText: self.appModel.cameraHUDText,
            cameraHUDKind: self.appModel.cameraHUDKind)
    }

    // MARK: - Lifecycle Helpers

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = (self.scenePhase == .active && self.preventSleep)
    }

    private func evaluateOnboardingPresentation(force: Bool) {
        if force {
            self.onboardingAllowSkip = true
            self.showOnboarding = true
            return
        }

        guard !self.didEvaluateOnboarding else { return }
        self.didEvaluateOnboarding = true
        let route = RootCanvas.startupPresentationRoute(
            gatewayConnected: self.appModel.gatewayServerName != nil,
            hasConnectedOnce: self.hasConnectedOnce,
            onboardingComplete: self.onboardingComplete,
            hasExistingGatewayConfig: self.hasExistingGatewayConfig(),
            shouldPresentOnLaunch: OnboardingStateStore.shouldPresentOnLaunch(appModel: self.appModel))
        switch route {
        case .none:
            break
        case .onboarding:
            self.onboardingAllowSkip = true
            self.showOnboarding = true
        case .settings:
            self.didAutoOpenSettings = true
            self.selectedTab = 2
        }
    }

    private func hasExistingGatewayConfig() -> Bool {
        if GatewaySettingsStore.loadLastGatewayConnection() != nil { return true }
        let manualHost = self.manualGatewayHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return self.manualGatewayEnabled && !manualHost.isEmpty
    }

    private func maybeAutoOpenSettings() {
        guard !self.didAutoOpenSettings else { return }
        guard !self.showOnboarding else { return }
        let route = RootCanvas.startupPresentationRoute(
            gatewayConnected: self.appModel.gatewayServerName != nil,
            hasConnectedOnce: self.hasConnectedOnce,
            onboardingComplete: self.onboardingComplete,
            hasExistingGatewayConfig: self.hasExistingGatewayConfig(),
            shouldPresentOnLaunch: false)
        guard route == .settings else { return }
        self.didAutoOpenSettings = true
        self.selectedTab = 2
    }

    private func maybeShowQuickSetup() {
        guard !self.quickSetupDismissed else { return }
        guard !self.showOnboarding else { return }
        guard self.appModel.gatewayServerName == nil else { return }
        guard !self.gatewayController.gateways.isEmpty else { return }
        self.showQuickSetup = true
    }
}

// Camera flash overlay (private in RootCanvas, duplicated here).
private struct CameraFlashOverlay: View {
    var nonce: Int

    @State private var opacity: CGFloat = 0
    @State private var task: Task<Void, Never>?

    var body: some View {
        Color.white
            .opacity(self.opacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onChange(of: self.nonce) { _, _ in
                self.task?.cancel()
                self.task = Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.08)) {
                        self.opacity = 0.85
                    }
                    try? await Task.sleep(nanoseconds: 110_000_000)
                    withAnimation(.easeOut(duration: 0.32)) {
                        self.opacity = 0
                    }
                }
            }
    }
}
