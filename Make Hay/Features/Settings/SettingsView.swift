//
//  SettingsView.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import SwiftUI

/// The settings view where users can configure their goals and app preferences.
///
/// **Why use @AppStorage?** This provides automatic persistence to UserDefaults,
/// ensuring the user's goal preference survives app restarts without requiring
/// a dedicated persistence layer for simple key-value data.
struct SettingsView: View {
    
    // MARK: - Dependencies
    
    /// The health service for checking authorization status. Injected for testability.
    let healthService: any HealthServiceProtocol
    
    /// The blocker service for app selection. Injected for testability.
    let blockerService: any BlockerServiceProtocol
    
    // MARK: - State
    
    /// The user's daily step goal, persisted to UserDefaults.
    /// Defaults to 10,000 steps, a commonly recommended daily target.
    @AppStorage("dailyStepGoal") private var dailyStepGoal: Int = 10_000
    
    /// Debug state for manually forcing app blocking on/off.
    /// Persisted to survive app restarts during testing sessions.
    @AppStorage("debugForceBlocking") private var isForceBlocking: Bool = false
    
    /// Tracks any error message to display in an alert.
    @State private var errorMessage: String?
    
    /// Tracks whether the error alert is shown.
    @State private var showingErrorAlert: Bool = false
    
    /// Reference to the current shield update task for cancellation handling.
    /// **Why store this?** Prevents race conditions when the toggle changes rapidly
    /// by cancelling any in-flight request before starting a new one.
    @State private var shieldUpdateTask: Task<Void, Never>?
    
    /// Tracks the current health authorization status for display.
    @State private var healthAuthStatus: HealthAuthorizationStatus = .notDetermined
    
    /// Tracks the current Screen Time authorization status for display.
    @State private var screenTimeAuthorized: Bool = false
    
    /// The minimum step goal allowed.
    private let minimumGoal: Int = 1_000
    
    /// The maximum step goal allowed.
    private let maximumGoal: Int = 50_000
    
    /// The increment/decrement step size for the stepper.
    private let stepIncrement: Int = 500
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            List {
                permissionsSection
                goalSection
                blockedAppsSection
                debugSection
            }
            .navigationTitle(String(localized: "Settings"))
            .task {
                await refreshPermissionStatus()
            }
            .refreshable {
                await refreshPermissionStatus()
            }
            .alert(
                String(localized: "Blocking Error"),
                isPresented: $showingErrorAlert
            ) {
                Button(String(localized: "OK"), role: .cancel) { }
            } message: {
                if let errorMessage {
                    Text(errorMessage)
                }
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
                
                if healthAuthStatus != .authorized {
                    Button(String(localized: "Request")) {
                        Task {
                            do {
                                try await healthService.requestAuthorization()
                                await refreshPermissionStatus()
                            } catch {
                                errorMessage = error.localizedDescription
                                showingErrorAlert = true
                            }
                        }
                    }
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
                
                if !screenTimeAuthorized {
                    Button(String(localized: "Request")) {
                        Task {
                            do {
                                try await blockerService.requestAuthorization()
                                await refreshPermissionStatus()
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
            
            // Open Settings Button
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text(String(localized: "Open App Settings"))
                }
            }
            .accessibilityIdentifier("openSettingsButton")
        } header: {
            Text(String(localized: "Permissions"))
        } footer: {
            Text(String(localized: "Both permissions are required for the app to function correctly. Pull to refresh status."))
        }
    }
    
    private var goalSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "figure.walk")
                        .foregroundStyle(.tint)
                        .font(.title2)
                    
                    Text(String(localized: "Daily Step Goal"))
                        .font(.headline)
                }
                
                Text(formattedGoal)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("currentGoalLabel")
                
                Stepper(
                    value: $dailyStepGoal,
                    in: minimumGoal...maximumGoal,
                    step: stepIncrement
                ) {
                    Text(String(localized: "Adjust by \(stepIncrement.formatted())"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("stepGoalStepper")
            }
            .padding(.vertical, 8)
        } header: {
            Text(String(localized: "Goals"))
        } footer: {
            Text(String(localized: "Set your daily step target. Apps will be blocked until you reach this goal."))
        }
    }
    
    private var blockedAppsSection: some View {
        Section {
            AppPickerView(blockerService: blockerService)
        } header: {
            Text(String(localized: "Blocked Apps"))
        } footer: {
            Text(String(localized: "Select the apps that will be blocked until you reach your daily step goal."))
        }
    }
    
    /// Debug section for manually testing app blocking without health data.
    ///
    /// **Why this exists:** FamilyControls and ManagedSettings only work on physical devices,
    /// not in the Simulator. This toggle allows developers to verify the blocking mechanism
    /// works independently of the health goal logic before full integration testing.
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
                        
                        Text(String(localized: "Manually override blocking regardless of step count"))
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
            Text(String(localized: "⚠️ This only works on a physical device. FamilyControls does not function in the iOS Simulator."))
                .foregroundStyle(.orange)
        }
    }
    
    // MARK: - Computed Properties
    
    /// Formats the step goal with thousands separator for display.
    private var formattedGoal: String {
        dailyStepGoal.formatted(.number)
    }
    
    // MARK: - Health Permission Display
    
    private var healthStatusIcon: String {
        switch healthAuthStatus {
        case .authorized:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .notDetermined:
            return "questionmark.circle.fill"
        }
    }
    
    private var healthStatusColor: Color {
        switch healthAuthStatus {
        case .authorized:
            return .green
        case .denied:
            return .red
        case .notDetermined:
            return .orange
        }
    }
    
    private var healthStatusText: String {
        switch healthAuthStatus {
        case .authorized:
            return String(localized: "Access granted to read step data")
        case .denied:
            return String(localized: "Access denied - check Settings")
        case .notDetermined:
            return String(localized: "Permission not yet requested")
        }
    }
    
    // MARK: - Screen Time Permission Display
    
    private var screenTimeStatusIcon: String {
        screenTimeAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill"
    }
    
    private var screenTimeStatusColor: Color {
        screenTimeAuthorized ? .green : .red
    }
    
    private var screenTimeStatusText: String {
        screenTimeAuthorized
            ? String(localized: "Family Controls authorized")
            : String(localized: "Not authorized - app blocking unavailable")
    }
    
    // MARK: - Methods
    
    /// Refreshes the current permission status from both services.
    ///
    /// **Why this is async?** We need to access actor-isolated properties,
    /// which requires awaiting across actor boundaries.
    private func refreshPermissionStatus() async {
        healthAuthStatus = await healthService.authorizationStatus
        screenTimeAuthorized = await blockerService.isAuthorized
    }
}

// MARK: - Preview

#Preview {
    SettingsView(
        healthService: MockHealthService(),
        blockerService: MockBlockerService()
    )
}
