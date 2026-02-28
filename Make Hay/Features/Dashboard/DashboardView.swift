//
//  DashboardView.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import SwiftUI
import HealthKit

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
    
    /// Tracks the current scene phase to respond to app lifecycle events.
    /// **Why observe scenePhase?** We need to refresh health data and check the gate
    /// every time the app comes to the foreground. This ensures blocking status stays
    /// in sync with health data even if the user walks outside the app.
    @Environment(\.scenePhase) private var scenePhase
    
    /// Tracks whether to trigger celebration haptic feedback.
    /// Set to true when the user achieves their goal, triggering a success haptic.
    @State private var triggerSuccessHaptic: Bool = false
    
    /// Reference to the scene phase update task for debouncing.
    /// **Why debounce?** Prevents unnecessary API calls during rapid app switching
    /// or multitasking scenarios where the app may foreground/background quickly.
    @State private var scenePhaseTask: Task<Void, Never>?
    
    /// Tracks the goal currently being edited (nil when not editing).
    @State private var editingGoal: GoalProgress?

    /// Controls presentation of the weekly schedule sheet.
    @State private var isShowingSchedule: Bool = false
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "Make Hay"))
                .background(Color.surfaceGrouped)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isShowingSchedule = true
                        } label: {
                            Image(systemName: "calendar")
                        }
                        .accessibilityIdentifier("weeklyScheduleButton")
                        .accessibilityLabel(String(localized: "Weekly Schedule"))
                    }
                }
                .sheet(isPresented: Binding(
                    get: { viewModel.isShowingAddGoal },
                    set: { viewModel.isShowingAddGoal = $0 }
                )) {
                    AddGoalView(viewModel: viewModel)
                }
                .sheet(item: $editingGoal) { goal in
                    editGoalSheet(for: goal)
                }
                .sheet(isPresented: $isShowingSchedule) {
                    WeeklyScheduleView(
                        viewModel: WeeklyScheduleViewModel(
                            dashboardViewModel: viewModel
                        )
                    )
                }
                .task {
                    await viewModel.onAppear()
                }
                .onDisappear {
                    // Stop the 60-second tick timer to avoid unnecessary work
                    // while the dashboard is off-screen.
                    viewModel.stopTimeTickTimer()
                    scenePhaseTask?.cancel()
                    scenePhaseTask = nil
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // Cancel any pending scene phase task to debounce rapid changes
                    scenePhaseTask?.cancel()
                    
                    if newPhase == .active {
                        // Debounce with a small delay to handle rapid transitions
                        scenePhaseTask = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }

                            // Refresh permission status first — the user may have
                            // just returned from Settings after re-granting access.
                            await viewModel.refreshPermissionStatus()
                            
                            let previousGoalMet = viewModel.isGoalMet
                            await viewModel.loadGoals()
                            
                            // Trigger haptic if goal was just achieved
                            if !previousGoalMet && viewModel.isGoalMet {
                                triggerSuccessHaptic = true
                            }
                        }
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
        ScrollView {
            VStack(spacing: 24) {
                // Permissions Banner — shown prominently above all other content
                // when HealthKit or Screen Time access has been revoked.
                if viewModel.isPermissionMissing {
                    permissionsBanner
                }

                // Banners Section
                VStack(spacing: 12) {
                    if viewModel.healthGoal.pendingGoal != nil {
                        pendingChangeBanner
                    }
                    
                    if viewModel.isGoalMet {
                        goalMetBanner
                    }
                }
                
                if viewModel.goalProgresses.isEmpty {
                    emptyGoalsDisplay
                } else {
                    // Goals Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "YOUR GOALS"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                        
                        goalProgressRows
                    }
                }
                
                if viewModel.isBlocking {
                    blockingStatusBadge
                }
            }
            .padding(.vertical, 24)
        }
        .refreshable {
            await viewModel.loadGoals()
        }
        .accessibilityIdentifier("Dashboard.goalsList")
    }
    
    /// Empty state prompting the user to add their first goal.
    /// **Why keep the centered layout?** Maintains the existing friendly
    /// onboarding feel without requiring the bar-based aesthetic.
    private var emptyGoalsDisplay: some View {
        VStack(spacing: 12) {
            Spacer()
                .frame(height: 60)
            
            Image(systemName: "plus.circle.fill")
                .font(.dashboardIcon)
                .foregroundStyle(.tint)
                .accessibilityIdentifier("emptyGoalsIcon")
            
            Text(String(localized: "Add your first goal to start"))
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("progressText")
            
            Button {
                viewModel.isShowingAddGoal = true
            } label: {
                Text(String(localized: "Get Started"))
                    .font(.headline)
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("getStartedButton")
        }
        .padding(.vertical)
    }
    
    /// Vertically stacked linear progress bars, one per enabled goal, inside a grouped card.
    /// **Why a card layout?** Groups related items visually, matching modern iOS Settings
    /// and Health app aesthetics. The inline "Add Goal" button is more discoverable
    /// and ergonomic than a top-right toolbar button.
    private var goalProgressRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.goalProgresses.enumerated()), id: \.element.id) { index, goal in
                GoalProgressRowView(progress: goal) {
                    editingGoal = goal
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                if index < viewModel.goalProgresses.count - 1 || viewModel.canAddMoreGoals {
                    Divider()
                        .padding(.leading, 56) // Align with text, skipping icon
                }
            }
            
            if viewModel.canAddMoreGoals {
                Button {
                    viewModel.isShowingAddGoal = true
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.statusSuccess)
                            .frame(width: 24, height: 24)
                        
                        Text(String(localized: "Add Goal"))
                            .font(.body)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("inlineAddGoalButton")
            }
        }
        .background(Color.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
    
    /// Inline celebration banner shown when all goals are met.
    /// **Why inline instead of overlay?** Keeps the progress bars visible at 100%
    /// so the user can see exactly what they achieved, while clearly communicating
    /// that apps are unlocked.
    private var goalMetBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.statusSuccess)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Goals Met!"))
                    .font(.headline)
                    .foregroundStyle(Color.statusSuccess)
                
                Text(String(localized: "Apps Unlocked"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.statusSuccess.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .accessibilityIdentifier("goalMetBanner")
    }
    
    /// Banner shown when a goal change is scheduled for tomorrow.
    /// **Why show this?** Provides transparency about pending changes and allows cancellation.
    private var pendingChangeBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.title3)
                .foregroundStyle(Color.statusInfo)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Goal Update Scheduled"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if let effectiveDate = viewModel.healthGoal.pendingGoalEffectiveDate {
                    Text("Takes effect at \(effectiveDate, style: .time)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                viewModel.cancelPendingGoal()
            } label: {
                Text(String(localized: "Cancel"))
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("cancelPendingButton")
        }
        .padding()
        .background(Color.statusInfo.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .accessibilityIdentifier("pendingChangeBanner")
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
    
    /// Badge indicating apps are currently blocked.
    /// **Why show this?** Provides clear feedback that the blocking feature is active,
    /// helping users understand why certain apps may be restricted.
    private var blockingStatusBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption)
            Text(String(localized: "Apps Blocked"))
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .foregroundStyle(Color.onboardingButtonContent)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.statusBlocked.gradient, in: Capsule())
        .accessibilityIdentifier("blockingStatusBadge")
    }

    /// Prominent banner alerting the user that one or both required permissions
    /// have been revoked. Delegates rendering to `PermissionsBannerView`.
    private var permissionsBanner: some View {
        PermissionsBannerView(
            healthStatus: viewModel.healthPermissionStatus,
            screenTimeAuthorized: viewModel.screenTimePermissionGranted
        )
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
                    await viewModel.requestAuthorizationAndLoad()
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
        .environment(\.dashboardViewModel, DashboardViewModel(healthService: mock, blockerService: MockBlockerService()))
}

#Preview("Loading State") {
    DashboardView()
}

#Preview("Error State") {
    DashboardView()
        .environment(\.dashboardViewModel, DashboardViewModel(healthService: ErrorThrowingMockHealthService(), blockerService: MockBlockerService()))
}

// MARK: - Preview Helper

/// A mock that always throws an error for preview purposes.
private actor ErrorThrowingMockHealthService: HealthServiceProtocol {
    var authorizationStatus: HealthAuthorizationStatus { .denied }
    
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
