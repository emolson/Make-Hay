//
//  DashboardViewModel.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import os.log
import SwiftUI

/// Supported goal types for dashboard display.
enum GoalType: String, Sendable, CaseIterable, Identifiable {
    case steps
    case activeEnergy
    case exercise
    case timeUnlock
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .steps:
            return String(localized: "Steps")
        case .activeEnergy:
            return String(localized: "Active Energy")
        case .exercise:
            return String(localized: "Exercise")
        case .timeUnlock:
            return String(localized: "Time")
        }
    }
    
    var iconName: String {
        switch self {
        case .steps:
            return "figure.walk"
        case .activeEnergy:
            return "flame"
        case .exercise:
            return "figure.run"
        case .timeUnlock:
            return "clock"
        }
    }
    
    var color: Color {
        switch self {
        case .steps:
            return .goalSteps
        case .activeEnergy:
            return .goalActiveEnergy
        case .exercise:
            return .goalExercise
        case .timeUnlock:
            return .goalTimeUnlock
        }
    }
}

/// Progress information for a single goal.
struct GoalProgress: Identifiable, Sendable, Equatable {
    let type: GoalType
    let current: Double
    let target: Double
    let progress: Double
    let isMet: Bool
    /// Optional ID for exercise goals to distinguish between multiple exercise goals.
    let exerciseGoalId: UUID?
    /// Optional exercise type label for display purposes.
    let exerciseType: ExerciseType?
    /// The schedule for this goal, used to display a schedule label on the row.
    let schedule: GoalSchedule
    
    var id: String {
        if let exerciseGoalId {
            return "\(type.rawValue)_\(exerciseGoalId.uuidString)"
        }
        return type.rawValue
    }
}

/// ViewModel for the Dashboard feature, managing health data state and user interactions.
///
/// **Why @MainActor?** All UI state updates must happen on the main thread. By marking
/// the entire class as @MainActor, we ensure all property updates are automatically
/// dispatched to the main thread, preventing data races.
@Observable
@MainActor
final class DashboardViewModel: GoalStatusProvider {

    private nonisolated static let traceCategory = "DashboardViewModel"
    
    // MARK: - State
    
    /// The current step count fetched from HealthKit.
    var currentSteps: Int = 0
    
    /// The current active energy fetched from HealthKit (kilocalories).
    var currentActiveEnergy: Double = 0
    
    /// The current exercise minutes fetched from HealthKit.
    /// Stores exercise minutes by goal ID.
    var currentExerciseMinutes: [UUID: Int] = [:]
    
    /// Ticks forward every 60 seconds so time-based computed properties re-evaluate.
    ///
    /// **Why this exists?** `goalProgresses` calls `currentMinutesSinceMidnight()` (via
    /// `Date()`), but since no `@Observable` property changes as real time passes,
    /// SwiftUI never re-evaluates the computed property. Incrementing this counter in
    /// a timer forces `@Observable` to notify views, keeping the time progress bar live.
    var timeTick: UInt = 0
    
    /// The user's health goal configuration (applies to every day).
    var healthGoal: HealthGoal = HealthGoal.load()
    
    /// Indicates whether a data fetch is in progress.
    var isLoading: Bool = false
    
    /// Indicates whether apps are currently being blocked.
    /// **Why expose this?** Provides transparency to users about blocking state,
    /// enabling UI feedback when apps are restricted.
    var isBlocking: Bool = false
    
    /// Error message to display if an operation fails.
    var errorMessage: String?
    
    /// Indicates whether an error is currently being displayed.
    var hasError: Bool {
        errorMessage != nil
    }

    /// Non-blocking warning shown when shield updates fail but health data loaded successfully.
    /// Unlike `errorMessage`, this does not replace the goals UI — it appears as a subtle banner.
    var shieldWarning: String?
    
    /// Controls presentation of the Add Goal sheet.
    var isShowingAddGoal: Bool = false
    
    /// The last day number the app checked for steps.
    /// Used to detect when a new day has started and reset blocking accordingly.
    ///
    /// **Why manual UserDefaults instead of `@AppStorage`?** All other persisted data uses
    /// `SharedStorage.appGroupDefaults`. Mixing suites is a maintenance risk. Using the
    /// app group suite directly keeps storage consistent across the app and extensions.
    @ObservationIgnored
    private var lastCheckedDayNumber: Int {
        get { SharedStorage.appGroupDefaults.integer(forKey: "lastCheckedDayNumber") }
        set { SharedStorage.appGroupDefaults.set(newValue, forKey: "lastCheckedDayNumber") }
    }

    /// Returns goal types that are available to be added (not currently enabled).
    /// **Why this matters?** Prevents users from adding duplicate goals and provides
    /// a clean way to determine which options to show in the AddGoalView.
    /// **Note:** Exercise goals can be added multiple times.
    /// **Why check the model directly?** `goalProgresses` only includes goals
    /// scheduled for today, so an inactive-but-enabled goal would appear
    /// "available" if we only checked the active list.
    var availableGoalTypes: [GoalType] {
        GoalType.allCases.filter { type in
            switch type {
            case .steps:
                return !healthGoal.stepGoal.isEnabled
            case .activeEnergy:
                return !healthGoal.activeEnergyGoal.isEnabled
            case .exercise:
                // Always allow adding exercise goals (supports multiple)
                return true
            case .timeUnlock:
                return !healthGoal.timeBlockGoal.isEnabled
            }
        }
    }
    
    /// Indicates whether the user can add more goals.
    var canAddMoreGoals: Bool {
        !availableGoalTypes.isEmpty
    }
    
    /// Returns all enabled goal progress values scheduled for today, ordered for display.
    var goalProgresses: [GoalProgress] {
        var items: [GoalProgress] = []
        
        if healthGoal.stepGoal.isEnabled && healthGoal.stepGoal.schedule.includestoday {
            let target = Double(max(healthGoal.stepGoal.target, 1))
            let current = Double(currentSteps)
            let progress = min(current / target, 1.0)
            items.append(GoalProgress(
                type: .steps,
                current: current,
                target: target,
                progress: progress,
                isMet: currentSteps >= healthGoal.stepGoal.target,
                exerciseGoalId: nil,
                exerciseType: nil,
                schedule: healthGoal.stepGoal.schedule
            ))
        }
        
        if healthGoal.activeEnergyGoal.isEnabled && healthGoal.activeEnergyGoal.schedule.includestoday {
            let target = Double(max(healthGoal.activeEnergyGoal.target, 1))
            let progress = min(currentActiveEnergy / target, 1.0)
            items.append(GoalProgress(
                type: .activeEnergy,
                current: currentActiveEnergy,
                target: target,
                progress: progress,
                isMet: currentActiveEnergy >= Double(healthGoal.activeEnergyGoal.target),
                exerciseGoalId: nil,
                exerciseType: nil,
                schedule: healthGoal.activeEnergyGoal.schedule
            ))
        }
        
        // Add progress for each enabled exercise goal scheduled for today
        for exerciseGoal in healthGoal.exerciseGoals where exerciseGoal.isEnabled && exerciseGoal.schedule.includestoday {
            let target = Double(max(exerciseGoal.targetMinutes, 1))
            let current = Double(currentExerciseMinutes[exerciseGoal.id] ?? 0)
            let progress = min(current / target, 1.0)
            items.append(GoalProgress(
                type: .exercise,
                current: current,
                target: target,
                progress: progress,
                isMet: current >= Double(exerciseGoal.targetMinutes),
                exerciseGoalId: exerciseGoal.id,
                exerciseType: exerciseGoal.exerciseType,
                schedule: exerciseGoal.schedule
            ))
        }

        if healthGoal.timeBlockGoal.isEnabled && healthGoal.timeBlockGoal.schedule.includestoday {
            // Read timeTick to create an @Observable dependency so SwiftUI
            // re-evaluates this property when the timer fires.
            _ = timeTick
            let nowMinutes = Double(currentMinutesSinceMidnight())
            let unlockMinutes = Double(max(healthGoal.timeBlockGoal.clampedUnlockMinutes, 1))
            let progress = min(nowMinutes / unlockMinutes, 1.0)
            let isMet = healthGoal.timeBlockGoal.clampedUnlockMinutes == 0
                || currentMinutesSinceMidnight() >= healthGoal.timeBlockGoal.clampedUnlockMinutes
            items.append(GoalProgress(
                type: .timeUnlock,
                current: nowMinutes,
                target: unlockMinutes,
                progress: progress,
                isMet: isMet,
                exerciseGoalId: nil,
                exerciseType: nil,
                schedule: healthGoal.timeBlockGoal.schedule
            ))
        }
        
        return items
    }

    /// Returns enabled goals that are NOT scheduled for today.
    /// **Why separate from `goalProgresses`?** Inactive goals don't track live progress
    /// or participate in blocking, but must still appear on the Dashboard (dimmed) so
    /// the user can see and manage their full goal list.
    var inactiveGoalProgresses: [GoalProgress] {
        var items: [GoalProgress] = []

        if healthGoal.stepGoal.isEnabled && !healthGoal.stepGoal.schedule.includestoday {
            let target = Double(max(healthGoal.stepGoal.target, 1))
            items.append(GoalProgress(
                type: .steps,
                current: 0,
                target: target,
                progress: 0,
                isMet: false,
                exerciseGoalId: nil,
                exerciseType: nil,
                schedule: healthGoal.stepGoal.schedule
            ))
        }

        if healthGoal.activeEnergyGoal.isEnabled && !healthGoal.activeEnergyGoal.schedule.includestoday {
            let target = Double(max(healthGoal.activeEnergyGoal.target, 1))
            items.append(GoalProgress(
                type: .activeEnergy,
                current: 0,
                target: target,
                progress: 0,
                isMet: false,
                exerciseGoalId: nil,
                exerciseType: nil,
                schedule: healthGoal.activeEnergyGoal.schedule
            ))
        }

        for exerciseGoal in healthGoal.exerciseGoals where exerciseGoal.isEnabled && !exerciseGoal.schedule.includestoday {
            let target = Double(max(exerciseGoal.targetMinutes, 1))
            items.append(GoalProgress(
                type: .exercise,
                current: 0,
                target: target,
                progress: 0,
                isMet: false,
                exerciseGoalId: exerciseGoal.id,
                exerciseType: exerciseGoal.exerciseType,
                schedule: exerciseGoal.schedule
            ))
        }

        if healthGoal.timeBlockGoal.isEnabled && !healthGoal.timeBlockGoal.schedule.includestoday {
            let unlockMinutes = Double(max(healthGoal.timeBlockGoal.clampedUnlockMinutes, 1))
            items.append(GoalProgress(
                type: .timeUnlock,
                current: 0,
                target: unlockMinutes,
                progress: 0,
                isMet: false,
                exerciseGoalId: nil,
                exerciseType: nil,
                schedule: healthGoal.timeBlockGoal.schedule
            ))
        }

        return items
    }
    
    /// Returns the primary goal to display at the center of the rings.
    var primaryGoalProgress: GoalProgress? {
        goalProgresses.first
    }
    
    /// Indicates whether the user has met their goal criteria based on blocking strategy.
    var isGoalMet: Bool {
        GoalBlockingEvaluator.isGoalMet(goal: healthGoal, snapshot: goalEvaluationSnapshot())
    }
    
    // MARK: - Dependencies
    
    private let healthService: any HealthServiceProtocol
    private let blockerService: any BlockerServiceProtocol
    private let backgroundHealthMonitor: any BackgroundHealthMonitorProtocol
    private let timeUnlockScheduler: any TimeUnlockScheduling

    private static let logger = AppLogger.logger(category: "DashboardViewModel")
    
    /// Reference to the running time-tick timer task.
    @ObservationIgnored
    private var timeTickTask: Task<Void, Never>?

    /// Re-entrancy flag for `loadGoals()`. Prevents multiple foreground / observer
    /// triggers from stacking redundant `syncNow()` calls on the actor.
    @ObservationIgnored
    private var isSyncing = false

    // MARK: - Initialization
    
    /// Creates a new DashboardViewModel with the specified services.
    /// - Parameters:
    ///   - healthService: The service to use for HealthKit authorization queries.
    ///   - blockerService: The service to use for managing app blocking.
    ///   - backgroundHealthMonitor: The single evaluation pipeline for health data fetching
    ///     and shield updates.
    ///   - timeUnlockScheduler: Scheduler for time-based goal device activity.
    init(
        healthService: any HealthServiceProtocol,
        blockerService: any BlockerServiceProtocol,
        backgroundHealthMonitor: any BackgroundHealthMonitorProtocol = MockBackgroundHealthMonitor(),
        timeUnlockScheduler: (any TimeUnlockScheduling)? = nil
    ) {
        self.healthService = healthService
        self.blockerService = blockerService
        self.backgroundHealthMonitor = backgroundHealthMonitor
        self.timeUnlockScheduler = timeUnlockScheduler ?? DeviceActivityTimeUnlockScheduler()

        refreshGoalFromStorage()

        // Seed UI state from the last persisted evaluation snapshot so the dashboard
        // renders real data instantly on cold start instead of zeros.
        if let snapshot = SharedStorage.lastEvaluationSnapshot {
            applyEvaluationResult(snapshot)
        }
    }
    
    // MARK: - Actions
    
    /// Called when the view appears. Refreshes goal configuration and syncs health data.
    ///
    /// **Why no authorization request?** Permission management is handled by the
    /// centralised `PermissionManager` at the `MainTabView` / `DashboardView` level.
    /// This method focuses on goal housekeeping and data sync.
    func onAppear() async {
        await onAppear(reason: "dashboard.onAppear")
    }

    func onAppear(reason: String) async {
        AppLogger.trace(
            category: Self.traceCategory,
            message: "onAppear started. reason=\(reason)"
        )
        refreshGoalFromStorage()
        updateTimeTickTimer()
        await loadGoals(reason: reason)
    }
    
    /// Fetches the current day's health metrics via the unified sync pipeline and
    /// updates the dashboard UI state.
    ///
    /// **Why delegate to `backgroundHealthMonitor.syncNow()`?** This eliminates the
    /// duplicate fetch → evaluate → shield-update pipeline that previously lived in the
    /// ViewModel. The monitor is now the single source of truth for health data and
    /// blocking decisions.
    func loadGoals() async {
        await loadGoals(reason: "unspecified")
    }

    func loadGoals(reason: String) async {
        // Prevent re-entrant calls from stacking redundant syncs.
        guard !isSyncing else {
            AppLogger.trace(
                category: Self.traceCategory,
                message: "loadGoals already in progress — skipping. reason=\(reason)"
            )
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        AppLogger.trace(
            category: Self.traceCategory,
            message: "loadGoals started. reason=\(reason)"
        )

        // Check if it's a new day before loading steps
        checkForNewDay()

        refreshGoalFromStorage()
        
        isLoading = true
        errorMessage = nil
        shieldWarning = nil
        
        defer { isLoading = false }
        
        do {
            let result = try await backgroundHealthMonitor.syncNow(reason: "dashboard.loadGoals.\(reason)")
            applyEvaluationResult(result)
            scheduleTimeUnlockIfNeeded()
            updateTimeTickTimer()
            AppLogger.trace(
                category: Self.traceCategory,
                message: "loadGoals completed successfully. reason=\(reason)"
            )
        } catch is CancellationError {
            // External cancellation (e.g. foreground debounce) — not an error.
            AppLogger.trace(
                category: Self.traceCategory,
                message: "loadGoals sync cancelled. reason=\(reason)"
            )
        } catch {
            // On failure, only reuse a cached snapshot when it is still fresh
            // for the current day. Otherwise keep the conservative local state
            // (for example, the midnight reset to zero progress).
            if let snapshot = SharedStorage.lastEvaluationSnapshot,
               snapshot.isFreshForCurrentDay() {
                applyEvaluationResult(snapshot)
            } else {
                isBlocking = GoalBlockingEvaluator.shouldBlock(
                    goal: healthGoal,
                    snapshot: goalEvaluationSnapshot()
                )
            }
            errorMessage = error.localizedDescription
            AppLogger.trace(
                category: Self.traceCategory,
                message: "loadGoals failed with surfaced error. reason=\(reason)"
            )
        }
    }
    
    /// Clears the current error message.
    func dismissError() {
        errorMessage = nil
    }

    /// Clears the shield warning banner.
    func dismissShieldWarning() {
        shieldWarning = nil
    }

    /// Whether the time-tick timer is needed right now.
    ///
    /// The timer only serves the time-unlock progress bar, so it should only
    /// run when a time-block goal is enabled and scheduled for today.
    private var needsTimeTickTimer: Bool {
        healthGoal.timeBlockGoal.isEnabled && healthGoal.timeBlockGoal.schedule.includestoday
    }

    /// Starts or stops the time-tick timer based on current goal state.
    ///
    /// Call after any change that might enable or disable the time-block goal
    /// (e.g., `loadGoals`, `addGoal`, `removeGoal`, `updateGoal`).
    func updateTimeTickTimer() {
        if needsTimeTickTimer {
            startTimeTickTimer()
        } else {
            stopTimeTickTimer()
        }
    }

    /// Starts a background timer that increments `timeTick` every 60 seconds.
    ///
    /// **Why 60 seconds?** The time-unlock progress bar displays minute-level granularity.
    /// A 1-minute tick keeps the bar visually current without burning CPU.
    func startTimeTickTimer() {
        guard timeTickTask == nil else { return }
        timeTickTask = Task { [weak self] in
            // **Why `do/catch` instead of `try?` + manual isCancelled?**
            // `Task.sleep` throws `CancellationError` when the task is cancelled.
            // Catching the error is the canonical Swift Concurrency exit pattern —
            // it avoids the redundant guard and makes intent explicit.
            do {
                while true {
                    try await Task.sleep(for: .seconds(60))
                    self?.timeTick &+= 1
                }
            } catch {
                // CancellationError — timer stopped, exit cleanly.
            }
        }
    }

    /// Stops the time-tick timer.
    func stopTimeTickTimer() {
        timeTickTask?.cancel()
        timeTickTask = nil
    }
    
    /// Adds a new goal of the specified type with the given target value.
    /// **Why update and reload?** Adding a goal enables it in the model, saves to disk,
    /// and then fetches fresh health data for that newly enabled goal.
    /// - Parameters:
    ///   - type: The type of goal to add.
    ///   - target: The target value for the goal.
    ///   - exerciseType: The exercise type (only used for exercise goals).
    func addGoal(type: GoalType, target: Double, exerciseType: ExerciseType = .any, schedule: GoalSchedule = .everyDay) async {
        switch type {
        case .steps:
            healthGoal.stepGoal.isEnabled = true
            healthGoal.stepGoal.target = Int(target)
            healthGoal.stepGoal.schedule = schedule
        case .activeEnergy:
            healthGoal.activeEnergyGoal.isEnabled = true
            healthGoal.activeEnergyGoal.target = Int(target)
            healthGoal.activeEnergyGoal.schedule = schedule
        case .exercise:
            let newExerciseGoal = ExerciseGoal(
                isEnabled: true,
                targetMinutes: Int(target),
                exerciseType: exerciseType,
                schedule: schedule
            )
            healthGoal.exerciseGoals.append(newExerciseGoal)
        case .timeUnlock:
            healthGoal.timeBlockGoal.isEnabled = true
            healthGoal.timeBlockGoal.unlockTimeMinutes = Int(target)
            healthGoal.timeBlockGoal.schedule = schedule
        }
        
        saveGoal()
        isShowingAddGoal = false
        
        // Reload to fetch data for the newly added goal
        await loadGoals()
    }
    
    /// Result of a gated goal removal request.
    /// **Why an enum?** The caller (DashboardView swipe action) needs to know
    /// whether to proceed immediately or present the deferred-change sheet.
    enum RemovalDecision: Sendable {
        /// The goal can be removed right now (all goals met or change is non-easier).
        case applyImmediately
        /// The removal must be deferred — carries the proposed goal for scheduling.
        case deferred(HealthGoal)
    }

    /// Gates a goal removal through the same anti-cheat flow as GoalConfigurationView.
    /// **Why not call `removeGoal` directly?** Removing a goal while blocked is an
    /// "easier" change that would let the user bypass app-blocking. This method
    /// checks `GoalChangeIntent` and `shouldDeferGoalEdits()` first.
    /// - Parameters:
    ///   - type: The type of goal to remove.
    ///   - exerciseGoalId: The ID of the exercise goal to remove (only for exercise goals).
    /// - Returns: Whether the removal can proceed now or must be deferred.
    func requestGoalRemoval(type: GoalType, exerciseGoalId: UUID? = nil) async -> RemovalDecision {
        let currentGoal = healthGoal
        var proposedGoal = currentGoal
        switch type {
        case .steps:
            proposedGoal.stepGoal.isEnabled = false
        case .activeEnergy:
            proposedGoal.activeEnergyGoal.isEnabled = false
        case .exercise:
            if let exerciseGoalId {
                proposedGoal.exerciseGoals.removeAll { $0.id == exerciseGoalId }
            }
        case .timeUnlock:
            proposedGoal.timeBlockGoal.isEnabled = false
        }

        let intent = GoalChangeIntent.determine(original: currentGoal, proposed: proposedGoal)

        if intent == .easier, shouldDeferGoalEdits() {
            return .deferred(proposedGoal)
        }
        return .applyImmediately
    }

    /// Removes a goal of the specified type.
    /// **Why save and sync?** Removing a goal disables it in the model,
    /// persists the change, and triggers a sync to re-evaluate blocking.
    /// - Parameters:
    ///   - type: The type of goal to remove.
    ///   - exerciseGoalId: The ID of the exercise goal to remove (only used for exercise goals).
    func removeGoal(type: GoalType, exerciseGoalId: UUID? = nil) async {
        switch type {
        case .steps:
            healthGoal.stepGoal.isEnabled = false
        case .activeEnergy:
            healthGoal.activeEnergyGoal.isEnabled = false
        case .exercise:
            if let exerciseGoalId {
                healthGoal.exerciseGoals.removeAll { $0.id == exerciseGoalId }
            }
        case .timeUnlock:
            healthGoal.timeBlockGoal.isEnabled = false
        }
        
        saveGoal()
        scheduleTimeUnlockIfNeeded()
        updateTimeTickTimer()
        
        // Re-evaluate blocking status after removing a goal
        await syncAndApply()
    }
    
    /// Updates an existing goal's target value.
    /// **Why separate from addGoal?** Updating a goal should not dismiss sheets or
    /// re-fetch all health data unnecessarily. It only persists the new target.
    /// - Parameters:
    ///   - type: The type of goal to update.
    ///   - target: The new target value for the goal.
    ///   - exerciseGoalId: The ID of the exercise goal to update (only used for exercise goals).
    ///   - exerciseType: The new exercise type (only used for exercise goals).
    func updateGoal(type: GoalType, target: Double, exerciseGoalId: UUID? = nil, exerciseType: ExerciseType = .any, schedule: GoalSchedule = .everyDay) async {
        switch type {
        case .steps:
            healthGoal.stepGoal.target = Int(target)
            healthGoal.stepGoal.schedule = schedule
        case .activeEnergy:
            healthGoal.activeEnergyGoal.target = Int(target)
            healthGoal.activeEnergyGoal.schedule = schedule
        case .exercise:
            if let exerciseGoalId,
               let index = healthGoal.exerciseGoals.firstIndex(where: { $0.id == exerciseGoalId }) {
                healthGoal.exerciseGoals[index].targetMinutes = Int(target)
                healthGoal.exerciseGoals[index].exerciseType = exerciseType
                healthGoal.exerciseGoals[index].schedule = schedule
            }
        case .timeUnlock:
            healthGoal.timeBlockGoal.unlockTimeMinutes = Int(target)
            healthGoal.timeBlockGoal.schedule = schedule
        }
        
        saveGoal()
        
        // Ensure time-based goals are rescheduled and blocking status is refreshed
        scheduleTimeUnlockIfNeeded()
        updateTimeTickTimer()
        await syncAndApply()
    }
    
    /// Applies an emergency goal change immediately after the breathing gate.
    /// **Why async?** Must update blocking status immediately after applying the change.
    /// - Parameter newGoal: The proposed goal configuration to apply now
    func applyEmergencyChange(_ newGoal: HealthGoal) async {
        // Apply the changes immediately
        healthGoal.stepGoal = newGoal.stepGoal
        healthGoal.activeEnergyGoal = newGoal.activeEnergyGoal
        healthGoal.exerciseGoals = newGoal.exerciseGoals
        healthGoal.timeBlockGoal = newGoal.timeBlockGoal
        healthGoal.blockingStrategy = .all
        
        saveGoal()
        
        // Update blocking status with the new goal
        scheduleTimeUnlockIfNeeded()
        await syncAndApply()
    }
    
    /// Returns whether easier goal edits should be deferred behind the pending-change flow.
    ///
    /// **Why use cached snapshot?** The evaluation snapshot is at most seconds old after
    /// a foreground sync. Using it avoids a redundant HealthKit round-trip and keeps
    /// the anti-cheat gate consistent with the data already displayed.
    func shouldDeferGoalEdits() -> Bool {
        let latestGoal = HealthGoal.load()
        return GoalGatekeeper.shouldDeferEdits(goal: latestGoal)
    }

    // MARK: - Private Methods

    /// Persists the health goal to App Group UserDefaults.
    private func saveGoal() {
        healthGoal.blockingStrategy = .all
        HealthGoal.save(healthGoal)
    }
    
    /// Checks if a new day has started and resets the blocking state if necessary.
    /// **Why this matters?** At midnight, the step count resets to 0, but the app might
    /// still have apps unblocked from yesterday. This function detects the date change
    /// and re-engages the block to ensure users start each day locked until they meet their goal.
    /// **Design:** Synchronous date comparison with immediate state update. The subsequent
    /// async sync pipeline will fetch today's data and refresh the shield state.
    private func checkForNewDay() {
        let currentDayNumber = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        
        // If stored day differs from today, it's a new day
        if lastCheckedDayNumber != currentDayNumber {
            lastCheckedDayNumber = currentDayNumber
            // Reset current values to force a fresh check
            // The subsequent health fetch will get today's actual (likely low) count
            // and checkGoalStatus() will re-engage blocking if needed
            currentSteps = 0
            currentActiveEnergy = 0
            currentExerciseMinutes = [:]
        }

        // Disable any one-time goals whose today-only schedule has expired.
        if healthGoal.expireGoalsIfNeeded() {
            saveGoal()
        }
    }
    
    /// Applies an evaluation result to the dashboard's observable state.
    ///
    /// **Why this method?** Centralises the mapping from `EvaluationResult` to UI state.
    /// Called after `syncNow()`, when seeding from a persisted snapshot on init, and as
    /// a fallback when a sync fails.
    func applyEvaluationResult(_ result: EvaluationResult) {
        currentSteps = result.steps
        currentActiveEnergy = result.activeEnergy
        currentExerciseMinutes = result.exerciseMinutesByGoalId
        isBlocking = result.shouldBlock
        shieldWarning = nil
    }

    /// Runs a sync via the background monitor and applies the result to UI state.
    ///
    /// **Why a helper?** Goal mutations (add, remove, update, emergency change) all
    /// need to re-evaluate blocking after persisting the goal change. This avoids
    /// duplicating the try/catch + fallback pattern.
    private func syncAndApply() async {
        do {
            let result = try await backgroundHealthMonitor.syncNow(reason: "dashboard.goalMutation")
            applyEvaluationResult(result)
        } catch {
            // Shield update failed — surface as a non-blocking warning.
            Self.logger.error("Sync after goal mutation failed.")
            shieldWarning = error.localizedDescription
        }
    }

    /// Reloads the latest health goal from shared storage.
    private func refreshGoalFromStorage() {
        healthGoal = HealthGoal.load()

        // Disable any one-time goals whose today-only schedule has expired.
        if healthGoal.expireGoalsIfNeeded() {
            saveGoal()
        }
        
        scheduleTimeUnlockIfNeeded()
    }

    /// Schedules the time-unlock monitor if a time-block goal is enabled.
    private func scheduleTimeUnlockIfNeeded() {
        guard healthGoal.timeBlockGoal.isEnabled else {
            timeUnlockScheduler.cancelUnlock()
            return
        }

        let minutes = healthGoal.timeBlockGoal.clampedUnlockMinutes
        guard minutes > 0 else {
            timeUnlockScheduler.cancelUnlock()
            return
        }

        do {
            try timeUnlockScheduler.scheduleUnlock(unlockMinutes: minutes)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func currentMinutesSinceMidnight(date: Date = Date()) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func goalEvaluationSnapshot() -> GoalEvaluationSnapshot {
        GoalEvaluationSnapshot(
            steps: currentSteps,
            activeEnergy: currentActiveEnergy,
            exerciseMinutesByGoalId: currentExerciseMinutes,
            currentMinutesSinceMidnight: currentMinutesSinceMidnight()
        )
    }
}
