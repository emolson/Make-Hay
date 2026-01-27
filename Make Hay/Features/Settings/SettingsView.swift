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
    
    /// Stored health goal data as JSON.
    @AppStorage(HealthGoal.storageKey) private var healthGoalData: String = ""
    
    /// The user's full goal configuration.
    @State private var healthGoal: HealthGoal = HealthGoal.load()
    
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
    private let minimumStepGoal: Int = 1_000
    
    /// The maximum step goal allowed.
    private let maximumStepGoal: Int = 50_000
    
    /// The increment/decrement step size for the stepper.
    private let stepIncrement: Int = 500
    
    /// The minimum active energy goal allowed (kcal).
    private let minimumActiveEnergy: Int = 50
    
    /// The maximum active energy goal allowed (kcal).
    private let maximumActiveEnergy: Int = 2_000
    
    /// The increment for active energy (kcal).
    private let activeEnergyIncrement: Int = 25
    
    /// The minimum exercise minutes goal allowed.
    private let minimumExerciseMinutes: Int = 5
    
    /// The maximum exercise minutes goal allowed.
    private let maximumExerciseMinutes: Int = 180
    
    /// The increment for exercise minutes.
    private let exerciseMinuteIncrement: Int = 5
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            List {
                goalSection
                blockedAppsSection
                permissionsSection
                debugSection
            }
            .navigationTitle(String(localized: "Settings"))
            .task {
                await refreshPermissionStatus()
                loadGoalFromStorage()
            }
            .refreshable {
                await refreshPermissionStatus()
            }
            .onChange(of: healthGoal) { _, newValue in
                persistGoal(newValue)
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
                goalToggleRow(
                    icon: "figure.walk",
                    title: String(localized: "Steps"),
                    subtitle: String(localized: "Track daily steps")
                ) {
                    Toggle(isOn: $healthGoal.stepGoal.isEnabled) { EmptyView() }
                        .labelsHidden()
                        .accessibilityIdentifier("toggleStepsGoal")
                }
                
                if healthGoal.stepGoal.isEnabled {
                    goalValueDisplay(
                        value: healthGoal.stepGoal.target.formatted(.number),
                        unit: String(localized: "steps")
                    )
                    
                    Stepper(
                        value: $healthGoal.stepGoal.target,
                        in: minimumStepGoal...maximumStepGoal,
                        step: stepIncrement
                    ) {
                        Text(String(localized: "Adjust by \(stepIncrement.formatted())"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("stepGoalStepper")
                }
                
                Divider().padding(.vertical, 6)
                
                goalToggleRow(
                    icon: "flame",
                    title: String(localized: "Active Energy"),
                    subtitle: String(localized: "Calories burned")
                ) {
                    Toggle(isOn: $healthGoal.activeEnergyGoal.isEnabled) { EmptyView() }
                        .labelsHidden()
                        .accessibilityIdentifier("toggleActiveEnergyGoal")
                }
                
                if healthGoal.activeEnergyGoal.isEnabled {
                    goalValueDisplay(
                        value: healthGoal.activeEnergyGoal.target.formatted(.number),
                        unit: String(localized: "kcal")
                    )
                    
                    Stepper(
                        value: $healthGoal.activeEnergyGoal.target,
                        in: minimumActiveEnergy...maximumActiveEnergy,
                        step: activeEnergyIncrement
                    ) {
                        Text(String(localized: "Adjust by \(activeEnergyIncrement.formatted())"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("activeEnergyGoalStepper")
                }
                
                Divider().padding(.vertical, 6)
                
                goalToggleRow(
                    icon: "figure.run",
                    title: String(localized: "Exercise"),
                    subtitle: String(localized: "Minutes of movement")
                ) {
                    Toggle(isOn: $healthGoal.exerciseGoal.isEnabled) { EmptyView() }
                        .labelsHidden()
                        .accessibilityIdentifier("toggleExerciseGoal")
                }
                
                if healthGoal.exerciseGoal.isEnabled {
                    goalValueDisplay(
                        value: healthGoal.exerciseGoal.targetMinutes.formatted(.number),
                        unit: String(localized: "min")
                    )
                    
                    Stepper(
                        value: $healthGoal.exerciseGoal.targetMinutes,
                        in: minimumExerciseMinutes...maximumExerciseMinutes,
                        step: exerciseMinuteIncrement
                    ) {
                        Text(String(localized: "Adjust by \(exerciseMinuteIncrement.formatted())"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("exerciseGoalStepper")
                    
                    Picker(String(localized: "Exercise Type"), selection: $healthGoal.exerciseGoal.exerciseType) {
                        ForEach(ExerciseType.allCases) { type in
                            Label(type.displayName, systemImage: type.iconName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.top, 12)
                    .accessibilityIdentifier("exerciseTypePicker")
                }
                
                Divider().padding(.vertical, 6)
                
                Picker(String(localized: "Unlock Apps When"), selection: $healthGoal.blockingStrategy) {
                    ForEach(BlockingStrategy.allCases) { strategy in
                        Text(strategy.displayName).tag(strategy)
                    }
                }
                .accessibilityIdentifier("blockingStrategyPicker")
            }
            .padding(.vertical, 8)
        } header: {
            Text(String(localized: "Goals"))
        } footer: {
            Text(String(localized: "Select the goals you want to complete to unlock your apps."))
        }
    }
    
    private var blockedAppsSection: some View {
        Section {
            AppPickerView(blockerService: blockerService)
        } header: {
            Text(String(localized: "Blocked Apps"))
        } footer: {
            Text(String(localized: "Select the apps that will be blocked until you reach your enabled goals."))
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
    
    // MARK: - Goal Helpers
    
    @ViewBuilder
    private func goalToggleRow(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder toggle: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            toggle()
        }
    }
    
    private func goalValueDisplay(value: String, unit: String) -> some View {
        HStack(spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .accessibilityIdentifier("goalValueDisplay")
    }
    
    private func loadGoalFromStorage() {
        if let decoded = HealthGoal.decode(from: healthGoalData) {
            healthGoal = decoded
        } else {
            healthGoal = HealthGoal.load()
            persistGoal(healthGoal)
        }
    }
    
    private func persistGoal(_ goal: HealthGoal) {
        healthGoalData = HealthGoal.encode(goal) ?? ""
        HealthGoal.save(goal)
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
            return String(localized: "Access granted to read health data")
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
