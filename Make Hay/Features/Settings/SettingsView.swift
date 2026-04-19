//
//  SettingsView.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import SwiftUI

/// The settings view where users can configure app permissions and blocked apps.
/// Goals are managed in the Dashboard for a unified experience.
struct SettingsView: View {

    private static let traceCategory = "SettingsView"

    #if DEBUG
        private static let developerBypassDuration: TimeInterval = 30
    #endif

    // MARK: - Dependencies

    /// Shared permission manager providing HealthKit and Screen Time authorization state.
    /// **Why `@Environment`?** Centralises permission logic that was previously duplicated
    /// between this view and `DashboardViewModel`. Mock-backed default keeps previews
    /// zero-config.
    @Environment(\.permissionManager) private var permissionManager

    /// Shared dashboard state used for the subtle daily-pass controls.
    @Environment(\.dashboardViewModel) private var dashboardViewModel

    /// SwiftUI environment action for opening the app's Settings page.
    @Environment(\.openURL) private var openURL

    /// The blocker service for app selection and debug shield toggling.
    @Environment(\.blockerService) private var blockerService

    // MARK: - State

    #if DEBUG
        /// Debug state for manually forcing app blocking on/off.
        /// Persisted to survive app restarts during testing sessions.
        @AppStorage("debugForceBlocking") private var isForceBlocking: Bool = false
    #endif

    /// Tracks any error message to display in an alert.
    @State private var errorMessage: String?

    /// Tracks whether the error alert is shown.
    @State private var showingErrorAlert: Bool = false

    /// Tracks whether the Health manual guidance alert is shown.
    /// **Why a separate alert?** When HealthKit's system prompt has already been presented
    /// once, calling `requestAuthorization()` may silently do nothing. This alert tells
    /// the user how to fix it manually in the Health app without falsely labeling the
    /// state as denied when readable samples are merely absent.
    @State private var showingHealthGuidance: Bool = false

    /// Controls presentation of the daily-pass confirmation dialog.
    @State private var isShowingPeekConfirmation: Bool = false

    #if DEBUG
        /// Reference to the current shield update task for cancellation handling.
        /// **Why store this?** Prevents race conditions when the toggle changes rapidly
        /// by cancelling any in-flight request before starting a new one.
        @State private var shieldUpdateTask: Task<Void, Never>?
    #endif

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                blockedAppsSection
                permissionsSection
                aboutSection
                #if DEBUG
                    debugSection
                #endif
            }
            .navigationTitle(String(localized: "Settings"))
            .task {
                AppLogger.trace(
                    category: Self.traceCategory,
                    message: "Settings task started. Refreshing permissions."
                )
                await refreshSettingsState(reason: "settings.task")
            }
            .refreshable {
                AppLogger.trace(
                    category: Self.traceCategory,
                    message: "Settings pull-to-refresh triggered."
                )
                await refreshSettingsState(reason: "settings.pullToRefresh")
            }
            .alert(
                String(localized: "Blocking Error"),
                isPresented: $showingErrorAlert
            ) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            }
            .sheet(isPresented: $isShowingPeekConfirmation) {
                GuardrailInterceptionView(context: .peekRequest) {
                    Task { await activateDailyPass() }
                }
            }
            .alert(
                String(localized: "Enable Health Access"),
                isPresented: $showingHealthGuidance
            ) {
                Button(String(localized: "Open Settings")) {
                    openAppSettings()
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                Text(
                    String(
                        localized:
                            "The Health permission prompt can only be shown once. To grant access, open the Health app, tap your profile (top right), then Apps & Services → Make Hay → turn on all categories."
                    ))
            }
        }
    }

    // MARK: - Sections

    /// Permissions section showing current authorization status for Health and Screen Time.
    ///
    /// **Why this section?** Users need visibility into permission states to understand
    /// why blocking might not work. This also provides a way to re-request permissions
    /// or navigate to Settings to fix issues.
    @ViewBuilder
    private var permissionsSection: some View {
        Section {
            // Health Permission Row
            HStack {
                Image(systemName: healthStatusIcon)
                    .foregroundStyle(healthStatusColor)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Apple Health"))
                        .font(.headline)

                    Text(healthStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if permissionManager.healthAuthorizationStatus == .notDetermined {
                    Button(String(localized: "Request"), action: requestHealthAccess)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("requestHealthButton")
                }
            }
            .accessibilityIdentifier("healthPermissionRow")

            // Screen Time Permission Row
            HStack {
                Image(systemName: screenTimeStatusIcon)
                    .foregroundStyle(screenTimeStatusColor)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Screen Time"))
                        .font(.headline)

                    Text(screenTimeStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !permissionManager.screenTimeAuthorized {
                    Button(String(localized: "Request")) {
                        Task {
                            do {
                                try await permissionManager.requestScreenTimePermission()
                            } catch {
                                errorMessage = error.localizedDescription
                                showingErrorAlert = true
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("requestScreenTimeButton")
                }
            }
            .accessibilityIdentifier("screenTimePermissionRow")

            if shouldShowOpenAppSettingsButton {
                Button {
                    openAppSettings()
                } label: {
                    HStack {
                        Image(systemName: "gear")
                        Text(String(localized: "Open App Settings"))
                    }
                }
                .accessibilityIdentifier("openSettingsButton")
            }

            if shouldShowReviewHealthPermissionsButton {
                Button(action: reviewHealthPermissions) {
                    HStack {
                        Image(systemName: "heart.text.square")
                        Text(String(localized: "Review Health Permissions"))
                    }
                }
                .accessibilityIdentifier("reviewHealthPermissionsButton")
            }
        } header: {
            Text(String(localized: "Permissions"))
        }
    }

    private var blockedAppsSection: some View {
        Section {
            AppPickerView()

            if shouldShowDailyPassControls {
                dailyPassRow
                #if DEBUG
                    developerBypassRow
                #endif
            }
        } header: {
            Text(String(localized: "Blocked Apps"))
        }
    }

    private static let privacyPolicyURL = URL(
        string: "https://emolson.github.io/Make-Hay/privacy/")!
    private static let supportURL = URL(string: "https://emolson.github.io/Make-Hay/support/")!

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            Link(destination: Self.privacyPolicyURL) {
                HStack {
                    Image(systemName: "hand.raised")
                    Text(String(localized: "Privacy Policy"))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("privacyPolicyLink")

            Link(destination: Self.supportURL) {
                HStack {
                    Image(systemName: "questionmark.circle")
                    Text(String(localized: "Support"))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("supportLink")
        } header: {
            Text(String(localized: "About"))
        }
    }

    /// Debug section for manually testing app blocking without health data.
    ///
    /// **Why this exists:** FamilyControls and ManagedSettings only work on physical devices,
    /// not in the Simulator. This toggle allows developers to verify the blocking mechanism
    /// works independently of the health goal logic before full integration testing.
    ///
    /// **Why `#if DEBUG`?** In production, this toggle could accidentally lock the user
    /// out of all their apps with no way to undo it. Restricting to debug builds ensures
    /// it's only available during development.
    #if DEBUG
        @ViewBuilder
        private var debugSection: some View {
            Section {
                Toggle(isOn: $isForceBlocking) {
                    HStack {
                        Image(systemName: isForceBlocking ? "lock.fill" : "lock.open")
                            .foregroundStyle(isForceBlocking ? .red : .secondary)
                            .font(.title2)
                            .contentTransition(.symbolEffect(.replace))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Force Block Apps"))
                                .font(.headline)

                            Text(
                                String(
                                    localized: "Manually override blocking regardless of step count"
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(.red)
                .accessibilityIdentifier("forceBlockToggle")
                .onChange(of: isForceBlocking) { _, newValue in
                    // Cancel any in-flight task to prevent race conditions
                    shieldUpdateTask?.cancel()

                    shieldUpdateTask = Task {
                        do {
                            try await blockerService.updateShields(shouldBlock: newValue)
                        } catch {
                            // Check if task was cancelled before showing error
                            guard !Task.isCancelled else { return }

                            // Revert the toggle state on failure
                            isForceBlocking = !newValue

                            // Show error alert to the user
                            errorMessage = error.localizedDescription
                            showingErrorAlert = true
                        }
                    }
                }
            } header: {
                Text(String(localized: "Debug"))
            } footer: {
                Text(
                    String(
                        localized:
                            "⚠️ This only works on a physical device. FamilyControls does not function in the iOS Simulator."
                    )
                )
                .foregroundStyle(.orange)
            }
        }
    #endif

    // MARK: - Health Permission Display

    private var healthStatusIcon: String {
        switch permissionManager.healthAuthorizationStatus {
        case .authorized:
            return "checkmark.circle.fill"
        case .unconfirmed:
            return "exclamationmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .notDetermined:
            return "questionmark.circle.fill"
        }
    }

    private var healthStatusColor: Color {
        switch permissionManager.healthAuthorizationStatus {
        case .authorized:
            return .statusSuccess
        case .unconfirmed:
            return .statusWarning
        case .denied:
            return .statusError
        case .notDetermined:
            return .statusWarning
        }
    }

    private var healthStatusText: String {
        switch permissionManager.healthAuthorizationStatus {
        case .authorized:
            return String(localized: "Access granted to read health data")
        case .unconfirmed:
            return String(
                localized: "Permission requested - review the Health app if tracking does not start"
            )
        case .denied:
            return String(localized: "Access denied - check Settings")
        case .notDetermined:
            return String(localized: "Permission not yet requested")
        }
    }

    // MARK: - Screen Time Permission Display

    private var screenTimeStatusIcon: String {
        permissionManager.screenTimeAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    private var screenTimeStatusColor: Color {
        permissionManager.screenTimeAuthorized ? .statusSuccess : .statusError
    }

    private var screenTimeStatusText: String {
        permissionManager.screenTimeAuthorized
            ? String(localized: "Family Controls authorized")
            : String(localized: "Not authorized - app blocking unavailable")
    }

    private var shouldShowOpenAppSettingsButton: Bool {
        !permissionManager.screenTimeAuthorized
    }

    private var shouldShowReviewHealthPermissionsButton: Bool {
        !permissionManager.healthAuthorizationStatus.isAuthorized
    }

    private var shouldShowDailyPassControls: Bool {
        dashboardViewModel.isPeekActive
            || dashboardViewModel.isPeekAvailable
    }

    @ViewBuilder
    private var dailyPassRow: some View {
        if dashboardViewModel.isPeekActive {
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .foregroundStyle(Color.statusWarning)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Pass Active"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(String(localized: "Apps unblock for \(formattedPeekTimeRemaining) more."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("peekCountdownSettingsRow")
        } else if dashboardViewModel.isPeekAvailable {
            Button {
                isShowingPeekConfirmation = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "hourglass")
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            String(
                                localized: "\(SharedStorage.nextPeekDurationMinutes)-Minute Pass")
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        Text(String(localized: "Keep this as a last-resort check-in."))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Text(String(localized: "Use"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("peekActivationButton")
            .accessibilityLabel(
                String(localized: "Use \(SharedStorage.nextPeekDurationMinutes)-Minute Pass"))
        }
    }

    #if DEBUG
        private var developerBypassActionText: String {
            dashboardViewModel.isPeekActive
                ? String(localized: "Active")
                : String(localized: "Use")
        }

        private var developerBypassRow: some View {
            Button {
                Task { await activateDeveloperBypass() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundStyle(Color.statusWarning)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Developer Bypass"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(
                            String(
                                localized:
                                    "Debug only: skip guardrails and unblock apps for 30 seconds."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Text(developerBypassActionText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(dashboardViewModel.isPeekActive)
            .accessibilityIdentifier("developerBypassButton")
            .accessibilityLabel(String(localized: "Use Developer Bypass"))
        }
    #endif

    private var formattedPeekTimeRemaining: String {
        let minutes = Int(dashboardViewModel.peekTimeRemaining) / 60
        let seconds = Int(dashboardViewModel.peekTimeRemaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Keeps Settings' permission and daily-pass state aligned with the shared evaluator.
    private func refreshSettingsState(reason: String) async {
        await permissionManager.refresh(reason: reason)

        let hadPersistedPeek = SharedStorage.peekExpirationDate != nil
        await dashboardViewModel.resumePeekIfNeeded()

        guard !dashboardViewModel.isPeekActive else { return }
        if hadPersistedPeek && dashboardViewModel.shieldWarning == nil {
            return
        }

        await dashboardViewModel.refreshBlockingState(reason: reason)
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    /// Activates the subtle daily pass and surfaces any activation failure to the alert.
    private func activateDailyPass() async {
        let result = await dashboardViewModel.activatePeek()

        if case .failed(let message) = result {
            errorMessage = message
            showingErrorAlert = true
        }
    }

    #if DEBUG
        /// Activates a short debug-only bypass using the same unblock and restore flow.
        private func activateDeveloperBypass() async {
            let result = await dashboardViewModel.activatePeek(
                duration: Self.developerBypassDuration,
                consumesUsageCount: false
            )

            if case .failed(let message) = result {
                errorMessage = message
                showingErrorAlert = true
            }
        }
    #endif

    /// Attempts to show the HealthKit permission prompt. If the prompt has already been
    /// shown without proven authorization, shows manual guidance instead, since HealthKit
    /// only presents its sheet once per type set.
    private func requestHealthAccess() {
        Task {
            AppLogger.trace(
                category: Self.traceCategory,
                message: "Health access request initiated from Settings."
            )

            await permissionManager.refresh(reason: "settings.requestHealthAccess.preflight")

            guard permissionManager.healthAuthorizationStatus == .notDetermined,
                !permissionManager.healthAuthorizationPromptShown
            else {
                showingHealthGuidance = true
                return
            }

            do {
                let status = try await permissionManager.requestHealthPermission()
                if status == .unconfirmed {
                    showingHealthGuidance = true
                }
            } catch {
                errorMessage = error.localizedDescription
                showingErrorAlert = true
            }
        }
    }

    private func reviewHealthPermissions() {
        showingHealthGuidance = true
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
