//
//  DashboardView.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import HealthKit
import SwiftUI

/// Wraps a proposed `HealthGoal` for `.sheet(item:)` presentation.
/// **Why not share `GoalConfigurationView.PendingGoalProposal`?** That type is
/// `private` to its file. Duplicating the 4-line struct avoids cross-file coupling.
private struct DashboardPendingGoalProposal: Identifiable {
    let id = UUID()
    let goal: HealthGoal
}

/// The main dashboard view showing the user's progress toward their health goal.
/// Displays step count, loading state, and error handling with retry capability.
///
/// **Why no business logic here?** Following MVVM, the View is purely declarative.
/// All state management and async operations are handled by DashboardViewModel.
struct DashboardView: View {

    // MARK: - State

    /// The shared dashboard view model, injected via the environment.
    /// **Why `@Environment` instead of `@State`?** The VM is shared state owned by the
    /// app root (via `AppDependencyContainer`), not by this view. `@Environment` is
    /// semantically correct for shared, externally-owned dependencies and makes
    /// previews trivially mockable via environment key defaults.
    @Environment(\.dashboardViewModel) private var viewModel

    /// Shared permission manager providing HealthKit and Screen Time authorization state.
    /// **Why `@Environment`?** Permissions are now managed by a centralised
    /// `PermissionManager` rather than duplicated in the ViewModel and SettingsView.
    @Environment(\.permissionManager) private var permissionManager

    /// Shared app navigation state used to route permission recovery to the Settings tab.
    @Environment(\.appNavigation) private var appNavigation

    /// Tracks the current scene phase to respond to app lifecycle events.
    /// **Why observe scenePhase?** We need to refresh the time-tick timer
    /// when the app comes back to the foreground so the time-block progress
    /// bar resumes updating.
    @Environment(\.scenePhase) private var scenePhase

    /// Tracks whether to trigger celebration haptic feedback.
    /// Set to true when the user achieves their goal, triggering a success haptic.
    @State private var triggerSuccessHaptic: Bool = false

    /// Tracks the previous value of `isGoalMet` for reactive haptic detection.
    @State private var previousGoalMet: Bool = false

    /// Tracks the goal currently being edited (nil when not editing).
    @State private var editingGoal: GoalProgress?

    /// Tracks a removal that must be deferred (swipe-to-delete while blocked).
    /// **Why separate from `editingGoal`?** Sheet destinations differ: edit opens
    /// `GoalConfigurationView`, while deferred removal opens `GuardrailInterceptionView`.
    @State private var pendingRemovalProposal: DashboardPendingGoalProposal?

    /// Controls presentation of the Mindful Peek interception flow.
    @State private var isShowingPeekInterception: Bool = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "Make Hay"))
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewModel.isShowingAddGoal = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(!viewModel.canAddMoreGoals)
                        .accessibilityIdentifier("addGoalToolbarButton")
                        .accessibilityLabel(String(localized: "Add Goal"))
                    }
                }
                .background(
                    viewModel.isGoalMet
                        ? Color.surfaceUnlocked.ignoresSafeArea()
                        : Color.surfaceGrouped.ignoresSafeArea()
                )
                .animation(.easeInOut(duration: 1.0), value: viewModel.isGoalMet)
                .sheet(
                    isPresented: Binding(
                        get: { viewModel.isShowingAddGoal },
                        set: { viewModel.isShowingAddGoal = $0 }
                    )
                ) {
                    AddGoalView(viewModel: viewModel)
                }
                .sheet(item: $editingGoal) { goal in
                    editGoalSheet(for: goal)
                }
                .sheet(item: $pendingRemovalProposal) { proposal in
                    GuardrailInterceptionView(context: .goalChange) {
                        Task {
                            await viewModel.applyEmergencyChange(proposal.goal)
                            pendingRemovalProposal = nil
                        }
                    }
                }
                .sheet(isPresented: $isShowingPeekInterception) {
                    GuardrailInterceptionView(context: .peekRequest) {
                        Task {
                            await viewModel.activatePeek()
                            isShowingPeekInterception = false
                        }
                    }
                }
                .task {
                    await permissionManager.refresh(reason: "dashboard.task")
                    await viewModel.onAppear(reason: "dashboard.task")
                }
                .onDisappear {
                    // Stop the 60-second tick timer to avoid unnecessary work
                    // while the dashboard is off-screen.
                    viewModel.stopTimeTickTimer()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // Resume the time-tick timer when returning to
                        // foreground. Health data sync is handled by
                        // MainTabView's unified scenePhase handler.
                        viewModel.updateTimeTickTimer()
                        Task { await viewModel.resumePeekIfNeeded() }
                    }
                }
                .onChange(of: viewModel.isGoalMet) { oldValue, newValue in
                    // Trigger haptic when goal transitions from not-met to met,
                    // regardless of which code path caused the change.
                    if !oldValue && newValue {
                        triggerSuccessHaptic = true
                    }
                }
                .sensoryFeedback(.success, trigger: triggerSuccessHaptic)
        }
    }

    // MARK: - Content Views

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            loadingView
        } else if viewModel.hasError {
            errorView
        } else {
            goalsView
        }
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .accessibilityIdentifier("loadingIndicator")

            Text(String(localized: "Loading your goals..."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var goalsView: some View {
        List {
            // Peek Countdown Banner — shown at the very top while a
            // Mindful Peek is active so the timer is always visible.
            if viewModel.isPeekActive {
                peekCountdownBanner
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }

            // Permissions Banner — shown prominently above all other content
            // when HealthKit or Screen Time access has been revoked.
            if permissionManager.isPermissionMissing {
                permissionsBanner
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }

            // Shield Warning Banner — shown when shield updates failed but
            // health data loaded successfully.
            if let shieldWarning = viewModel.shieldWarning {
                shieldWarningBanner(message: shieldWarning)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }

            // Stale Data Banner — visible when background evaluation hasn't
            // run recently and the displayed blocking state may be outdated.
            if SharedStorage.isEvaluationStale && !viewModel.isLoading {
                staleDataBanner
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }

            if viewModel.goalProgresses.isEmpty && viewModel.inactiveGoalProgresses.isEmpty {
                emptyGoalsDisplay
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                // Active Goals Section — goals scheduled for today.
                // Each row supports swipe-to-delete.
                // **Why List instead of ScrollView?** SwiftUI's `.swipeActions`
                // modifier only works inside `List`. Converting enables native
                // swipe-to-delete with no custom gesture handling.
                if !viewModel.goalProgresses.isEmpty {
                    Section {
                        ForEach(viewModel.goalProgresses) { goal in
                            GoalProgressRowView(progress: goal) {
                                editingGoal = goal
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    Task {
                                        let decision = await viewModel.requestGoalRemoval(
                                            type: goal.type,
                                            exerciseGoalId: goal.exerciseGoalId
                                        )
                                        switch decision {
                                        case .applyImmediately:
                                            await viewModel.removeGoal(
                                                type: goal.type,
                                                exerciseGoalId: goal.exerciseGoalId
                                            )
                                        case .deferred(let proposedGoal):
                                            pendingRemovalProposal = DashboardPendingGoalProposal(
                                                goal: proposedGoal)
                                        }
                                    }
                                } label: {
                                    Label(String(localized: "Delete"), systemImage: "trash")
                                }
                                .tint(.red)
                                .accessibilityIdentifier("deleteGoalAction.\(goal.id)")
                            }
                        }
                    } header: {
                        Text(String(localized: "YOUR GOALS"))
                    }
                } else {
                    // All goals exist but none are scheduled for today
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "moon.zzz")
                                .foregroundStyle(.tertiary)
                            Text(String(localized: "No goals scheduled for today"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                    } header: {
                        Text(String(localized: "YOUR GOALS"))
                    }
                }

                // Inactive Goals Section — enabled goals not scheduled for today.
                // Shown dimmed below active goals so the user can still see and
                // manage their full goal list.
                if !viewModel.inactiveGoalProgresses.isEmpty {
                    Section {
                        ForEach(viewModel.inactiveGoalProgresses) { goal in
                            GoalProgressRowView(progress: goal, isInactive: true) {
                                editingGoal = goal
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    Task {
                                        let decision = await viewModel.requestGoalRemoval(
                                            type: goal.type,
                                            exerciseGoalId: goal.exerciseGoalId
                                        )
                                        switch decision {
                                        case .applyImmediately:
                                            await viewModel.removeGoal(
                                                type: goal.type,
                                                exerciseGoalId: goal.exerciseGoalId
                                            )
                                        case .deferred(let proposedGoal):
                                            pendingRemovalProposal = DashboardPendingGoalProposal(
                                                goal: proposedGoal)
                                        }
                                    }
                                } label: {
                                    Label(String(localized: "Delete"), systemImage: "trash")
                                }
                                .tint(.red)
                                .accessibilityIdentifier("deleteGoalAction.\(goal.id)")
                            }
                        }
                    } header: {
                        Text(String(localized: "NOT SCHEDULED TODAY"))
                    }
                }

                // Mindful Peek Section — activation button or "used" indicator.
                // Shown only while the user is currently blocked.
                if viewModel.isBlocking {
                    if viewModel.isPeekAvailable {
                        Section {
                            Button {
                                isShowingPeekInterception = true
                            } label: {
                                Label(
                                    String(localized: "I need to check something quickly"),
                                    systemImage: "eye.circle"
                                )
                            }
                            .accessibilityIdentifier("peekActivationButton")
                        }
                    } else if viewModel.isPeekUsedToday {
                        Section {
                            HStack(spacing: 8) {
                                Image(systemName: "eye.slash")
                                    .foregroundStyle(.tertiary)
                                Text(String(localized: "Daily peek used"))
                                    .font(.subheadline)
                                    .foregroundStyle(.tertiary)
                            }
                            .accessibilityIdentifier("peekUsedIndicator")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable {
            await viewModel.loadGoals(reason: "dashboard.pullToRefresh")
        }
        .accessibilityIdentifier("Dashboard.goalsList")
    }

    /// Empty state prompting the user to add their first goal.
    /// **Why centered?** Provides a clean, focused starting point that avoids
    /// cluttering the list while no goals are present.
    private var emptyGoalsDisplay: some View {
        VStack(spacing: 16) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityIdentifier("emptyGoalsIcon")

            VStack(spacing: 8) {
                Text(String(localized: "No Goals Yet"))
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(String(localized: "Add a health goal to start unblocking your apps."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            Button {
                viewModel.isShowingAddGoal = true
            } label: {
                Text(String(localized: "Add First Goal"))
                    .font(.headline)
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
            .accessibilityIdentifier("getStartedButton")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    /// Banner warning that a shield update failed. The blocking state displayed
    /// may not match the actual device state.
    private func shieldWarningBanner(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.slash")
                .font(.title3)
                .foregroundStyle(Color.statusWarning)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Blocking Update Failed"))
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await viewModel.loadGoals(reason: "dashboard.shieldWarningRetry") }
            } label: {
                Text(String(localized: "Retry"))
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("shieldWarningRetryButton")
        }
        .padding()
        .background(Color.statusWarning.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .accessibilityIdentifier("shieldWarningBanner")
    }

    /// Banner shown when the last background health evaluation is older than the
    /// staleness threshold. Blocking state may be outdated.
    private var staleDataBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3)
                .foregroundStyle(Color.statusWarning)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Data May Be Outdated"))
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(
                    String(
                        localized:
                            "Background health sync hasn't run recently. Pull to refresh or tap Retry."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await viewModel.loadGoals(reason: "dashboard.staleDataRetry") }
            } label: {
                Text(String(localized: "Retry"))
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("staleDataRetryButton")
        }
        .padding()
        .background(Color.statusWarning.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .accessibilityIdentifier("staleDataBanner")
    }

    /// Creates an edit sheet for the specified goal progress.
    /// **Why a separate method?** Extracts the complexity of finding the exercise goal
    /// and constructing the proper edit mode from the sheet modifier.
    @ViewBuilder
    private func editGoalSheet(for progress: GoalProgress) -> some View {
        let exerciseGoal: ExerciseGoal? = {
            if progress.type == .exercise, let id = progress.exerciseGoalId {
                return viewModel.healthGoal.exerciseGoals.first { $0.id == id }
            }
            return nil
        }()

        NavigationStack {
            GoalConfigurationView(
                viewModel: viewModel,
                goalType: progress.type,
                mode: .edit(exerciseGoalId: progress.exerciseGoalId),
                exerciseGoal: exerciseGoal
            )
        }
    }

    /// Prominent banner alerting the user that one or both required permissions
    /// have been revoked. Delegates rendering to `PermissionsBannerView`.
    private var permissionsBanner: some View {
        PermissionsBannerView(
            healthStatus: permissionManager.healthAuthorizationStatus,
            screenTimeAuthorized: permissionManager.screenTimeAuthorized,
            onOpenSettings: {
                appNavigation.selectedTab = .settings
            }
        )
    }

    /// Countdown banner displayed while a Mindful Peek is active.
    /// Shows remaining time so the user can gauge urgency at a glance.
    private var peekCountdownBanner: some View {
        let minutes = Int(viewModel.peekTimeRemaining) / 60
        let seconds = Int(viewModel.peekTimeRemaining) % 60
        let formatted = String(format: "%d:%02d", minutes, seconds)

        return HStack(spacing: 10) {
            Image(systemName: "timer")
                .foregroundStyle(Color.statusWarning)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Apps unblocked for \(formatted)"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(String(localized: "Get in, get out."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color.statusWarning.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .accessibilityIdentifier("peekCountdownBanner")
    }

    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.dashboardErrorIcon)
                .foregroundStyle(Color.statusWarning)
                .accessibilityIdentifier("errorIcon")

            Text(String(localized: "Unable to Load Goals"))
                .font(.title2)
                .fontWeight(.semibold)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .accessibilityIdentifier("errorMessage")
            }

            Button {
                Task {
                    await viewModel.loadGoals(reason: "dashboard.errorRetry")
                }
            } label: {
                Text(String(localized: "Retry"))
                    .font(.headline)
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("retryButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityIdentifier("Dashboard.errorView")
    }
}

// MARK: - Preview

#Preview("Progress - 50%") {
    // MockHealthService defaults (5,000 steps, 350 kcal, 20 min) are
    // reasonable for a "50%" preview. Environment defaults provide mock services.
    DashboardView()
}

#Preview("Goal Met") {
    // Override the default environment with high-value mocks to show "goal met" state.
    let mock = MockHealthService(steps: 12_500, activeEnergy: 650, exerciseMinutes: 45)
    DashboardView()
        .environment(
            \.dashboardViewModel,
            DashboardViewModel(healthService: mock, blockerService: MockBlockerService()))
}

#Preview("Loading State") {
    DashboardView()
}

#Preview("Error State") {
    DashboardView()
        .environment(
            \.dashboardViewModel,
            DashboardViewModel(
                healthService: ErrorThrowingMockHealthService(),
                blockerService: MockBlockerService()))
}

#Preview("Peek Active") {
    let vm = DashboardViewModel(
        healthService: MockHealthService(), blockerService: MockBlockerService())
    vm.isPeekActive = true
    vm.peekTimeRemaining = 142
    return DashboardView()
        .environment(\.dashboardViewModel, vm)
}

// MARK: - Preview Helper

/// A mock that always throws an error for preview purposes.
private actor ErrorThrowingMockHealthService: HealthServiceProtocol {
    var authorizationStatus: HealthAuthorizationStatus {
        get async { .denied }
    }

    var authorizationPromptShown: Bool {
        get async { true }
    }

    func requestAuthorization() async throws {
        throw HealthServiceError.authorizationDenied
    }

    func fetchDailySteps() async throws -> Int {
        throw HealthServiceError.authorizationDenied
    }

    func fetchActiveEnergy() async throws -> Double {
        throw HealthServiceError.authorizationDenied
    }

    func fetchExerciseMinutes(for activityType: HKWorkoutActivityType?) async throws -> Int {
        throw HealthServiceError.authorizationDenied
    }

    func fetchCurrentData() async throws -> HealthCurrentData {
        throw HealthServiceError.authorizationDenied
    }
}
