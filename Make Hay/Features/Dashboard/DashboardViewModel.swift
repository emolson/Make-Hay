//
//  DashboardViewModel.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import SwiftUI
import HealthKit

/// Read-only provider exposing current gate state for reuse by other feature ViewModels.
protocol GoalStatusProvider: AnyObject {
    var isBlocking: Bool { get }
}

/// Protocol exposing weekly schedule goal-editing capabilities to feature views/ViewModels.
///
/// **Why a protocol?** Keeps feature modules decoupled from the concrete
/// `DashboardViewModel` implementation while preserving a single source of truth.
@MainActor
protocol ScheduleGoalManaging: AnyObject {
    var weeklySchedule: WeeklyGoalSchedule { get }
    var todayWeekday: Int { get }

    func schedulePendingGoal(_ newGoal: HealthGoal, forWeekday weekday: Int?)
    func applyEmergencyChange(_ newGoal: HealthGoal) async
    func shouldDeferGoalEdits() async -> Bool
    func updateGoal(type: GoalType, target: Double, exerciseGoalId: UUID?, exerciseType: ExerciseType, forWeekday weekday: Int) async
    func addGoal(type: GoalType, target: Double, exerciseType: ExerciseType, forWeekday weekday: Int) async
    func removeGoal(type: GoalType, exerciseGoalId: UUID?, forWeekday weekday: Int) async
}

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
final class DashboardViewModel: GoalStatusProvider, ScheduleGoalManaging {
    
    // MARK: - State
    
    /// The current step count fetched from HealthKit.
    var currentSteps: Int = 0
    
    /// The current active energy fetched from HealthKit (kilocalories).
    var currentActiveEnergy: Double = 0
    
    /// The current exercise minutes fetched from HealthKit.
    /// Stores exercise minutes by goal ID.
    var currentExerciseMinutes: [UUID: Int] = [:]
    
    /// The user's weekly goal schedule, containing a `HealthGoal` per weekday.
    /// **Why weekly?** Allows different goals on different days (e.g., rest on weekends).
    var weeklySchedule: WeeklyGoalSchedule = WeeklyGoalSchedule.load()

    /// The current weekday (1 = Sunday … 7 = Saturday).
    /// Re-derived on new-day detection so `healthGoal` always reflects today.
    var todayWeekday: Int = Calendar.current.component(.weekday, from: Date())

    /// Convenience accessor for today's goal configuration.
    /// **Why computed?** All existing code reads `healthGoal`; this keeps the diff minimal
    /// while routing through the weekly schedule. Writes go through `setTodayGoal(_:)`.
    var healthGoal: HealthGoal {
        get { weeklySchedule.goal(for: todayWeekday) }
        set { weeklySchedule.setGoal(newValue, for: todayWeekday) }
    }
    
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
    
    /// Controls presentation of the Add Goal sheet.
    var isShowingAddGoal: Bool = false
    
    /// The last day number the app checked for steps.
    /// Used to detect when a new day has started and reset blocking accordingly.
    @ObservationIgnored
    @AppStorage("lastCheckedDayNumber") private var lastCheckedDayNumber: Int = 0

    /// Returns goal types that are available to be added (not currently enabled).
    /// **Why this matters?** Prevents users from adding duplicate goals and provides
    /// a clean way to determine which options to show in the AddGoalView.
    /// **Note:** Exercise goals can be added multiple times.
    var availableGoalTypes: [GoalType] {
        GoalType.allCases.filter { type in
            switch type {
            case .exercise:
                // Always allow adding exercise goals (supports multiple)
                return true
            default:
                // Other goal types can only exist once
                return !goalProgresses.contains { $0.type == type }
            }
        }
    }
    
    /// Indicates whether the user can add more goals.
    var canAddMoreGoals: Bool {
        !availableGoalTypes.isEmpty
    }
    
    /// Returns all enabled goal progress values, ordered for display.
    var goalProgresses: [GoalProgress] {
        var items: [GoalProgress] = []
        
        if healthGoal.stepGoal.isEnabled {
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
                exerciseType: nil
            ))
        }
        
        if healthGoal.activeEnergyGoal.isEnabled {
            let target = Double(max(healthGoal.activeEnergyGoal.target, 1))
            let progress = min(currentActiveEnergy / target, 1.0)
            items.append(GoalProgress(
                type: .activeEnergy,
                current: currentActiveEnergy,
                target: target,
                progress: progress,
                isMet: currentActiveEnergy >= Double(healthGoal.activeEnergyGoal.target),
                exerciseGoalId: nil,
                exerciseType: nil
            ))
        }
        
        // Add progress for each enabled exercise goal
        for exerciseGoal in healthGoal.exerciseGoals where exerciseGoal.isEnabled {
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
                exerciseType: exerciseGoal.exerciseType
            ))
        }

        if healthGoal.timeBlockGoal.isEnabled {
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
                exerciseType: nil
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
    private let timeUnlockScheduler: any TimeUnlockScheduling
    
    // MARK: - Initialization
    
    /// Creates a new DashboardViewModel with the specified services.
    /// - Parameters:
    ///   - healthService: The service to use for fetching health data.
    ///   - blockerService: The service to use for managing app blocking.
    ///   Both are injected as protocols to enable testing with mocks.
    init(
        healthService: any HealthServiceProtocol,
        blockerService: any BlockerServiceProtocol,
        timeUnlockScheduler: (any TimeUnlockScheduling)? = nil
    ) {
        self.healthService = healthService
        self.blockerService = blockerService
        self.timeUnlockScheduler = timeUnlockScheduler ?? DeviceActivityTimeUnlockScheduler()
        refreshGoalFromStorage()
    }
    
    // MARK: - Actions
    
    /// Called when the view appears. Ensures authorization and triggers initial data load.
    /// **Why request authorization here?** HealthKit requires explicit authorization before
    /// queries can succeed. Requesting authorization when already granted is a no-op.
    func onAppear() async {
        refreshGoalFromStorage()
        _ = try? await blockerService.applyPendingSelectionIfReady()
        await requestAuthorizationAndLoad()
    }
    
    /// Fetches the current day's health metrics from HealthKit.
    /// Updates current values, loading state, and error state.
    /// Note: This assumes authorization has already been granted.
    func loadGoals() async {
        // Check if it's a new day before loading steps
        checkForNewDay()
        
        // Apply any pending goal changes that are now effective
        refreshGoalFromStorage()
        _ = try? await blockerService.applyPendingSelectionIfReady()
        
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            let results = try await fetchEnabledGoals()
            currentSteps = results.steps
            currentActiveEnergy = results.activeEnergy
            currentExerciseMinutes = results.exerciseMinutes
            scheduleTimeUnlockIfNeeded()
            // Check and update blocking status after loading metrics
            await checkGoalStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    /// Requests HealthKit authorization and then loads steps.
    /// Use this when the user taps retry after an authorization error.
    func requestAuthorizationAndLoad() async {
        // Check if it's a new day before loading steps
        checkForNewDay()
        
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            try await healthService.requestAuthorization()
            refreshGoalFromStorage()
            _ = try? await blockerService.applyPendingSelectionIfReady()
            let results = try await fetchEnabledGoals()
            currentSteps = results.steps
            currentActiveEnergy = results.activeEnergy
            currentExerciseMinutes = results.exerciseMinutes
            scheduleTimeUnlockIfNeeded()
            // Check and update blocking status after loading metrics
            await checkGoalStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    /// Clears the current error message.
    func dismissError() {
        errorMessage = nil
    }
    
    /// Adds a new goal of the specified type with the given target value.
    /// **Why update and reload?** Adding a goal enables it in the model, saves to disk,
    /// and then fetches fresh health data for that newly enabled goal.
    /// - Parameters:
    ///   - type: The type of goal to add.
    ///   - target: The target value for the goal.
    ///   - exerciseType: The exercise type (only used for exercise goals).
    func addGoal(type: GoalType, target: Double, exerciseType: ExerciseType = .any) async {
        switch type {
        case .steps:
            healthGoal.stepGoal.isEnabled = true
            healthGoal.stepGoal.target = Int(target)
        case .activeEnergy:
            healthGoal.activeEnergyGoal.isEnabled = true
            healthGoal.activeEnergyGoal.target = Int(target)
        case .exercise:
            let newExerciseGoal = ExerciseGoal(
                isEnabled: true,
                targetMinutes: Int(target),
                exerciseType: exerciseType
            )
            healthGoal.exerciseGoals.append(newExerciseGoal)
        case .timeUnlock:
            healthGoal.timeBlockGoal.isEnabled = true
            healthGoal.timeBlockGoal.unlockTimeMinutes = Int(target)
        }
        
        saveSchedule()
        isShowingAddGoal = false
        
        // Reload to fetch data for the newly added goal
        await loadGoals()
    }
    
    /// Removes a goal of the specified type.
    /// **Why save and check status?** Removing a goal disables it in the model,
    /// persists the change, and recalculates whether apps should be blocked.
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
        
        saveSchedule()
        scheduleTimeUnlockIfNeeded()
        
        // Re-check blocking status after removing a goal
        await checkGoalStatus()
    }
    
    /// Updates an existing goal's target value.
    /// **Why separate from addGoal?** Updating a goal should not dismiss sheets or
    /// re-fetch all health data unnecessarily. It only persists the new target.
    /// - Parameters:
    ///   - type: The type of goal to update.
    ///   - target: The new target value for the goal.
    ///   - exerciseGoalId: The ID of the exercise goal to update (only used for exercise goals).
    ///   - exerciseType: The new exercise type (only used for exercise goals).
    func updateGoal(type: GoalType, target: Double, exerciseGoalId: UUID? = nil, exerciseType: ExerciseType = .any) async {
        switch type {
        case .steps:
            healthGoal.stepGoal.target = Int(target)
        case .activeEnergy:
            healthGoal.activeEnergyGoal.target = Int(target)
        case .exercise:
            if let exerciseGoalId,
               let index = healthGoal.exerciseGoals.firstIndex(where: { $0.id == exerciseGoalId }) {
                healthGoal.exerciseGoals[index].targetMinutes = Int(target)
                healthGoal.exerciseGoals[index].exerciseType = exerciseType
            }
        case .timeUnlock:
            healthGoal.timeBlockGoal.unlockTimeMinutes = Int(target)
        }
        
        saveSchedule()
        
        // Ensure time-based goals are rescheduled and blocking status is refreshed
        scheduleTimeUnlockIfNeeded()
        await checkGoalStatus()
    }
    
    /// Schedules a goal change to take effect at the next occurrence of the target weekday.
    ///
    /// **Why weekday-aware?** The weekly schedule allows editing future days directly.
    /// When editing today while blocked, the change is deferred to the *next* occurrence
    /// of today (7 days later), extending the existing "Next-Day Effect" to the weekly model.
    ///
    /// - Parameters:
    ///   - newGoal: The proposed goal configuration to apply.
    ///   - weekday: The weekday this change targets (defaults to `todayWeekday`).
    func schedulePendingGoal(_ newGoal: HealthGoal, forWeekday weekday: Int? = nil) {
        let targetWeekday = weekday ?? todayWeekday
        var dayGoal = weeklySchedule.goal(for: targetWeekday)
        var normalizedGoal = newGoal
        normalizedGoal.blockingStrategy = .all
        dayGoal.pendingGoal = PendingHealthGoal(from: normalizedGoal)
        if targetWeekday == todayWeekday {
            // Editing today while blocked → defer to next occurrence (7 days)
            dayGoal.pendingGoalEffectiveDate = Date.nextOccurrence(of: targetWeekday)
        } else {
            // Editing a future day → defer to next midnight of that weekday
            dayGoal.pendingGoalEffectiveDate = Date.nextOccurrence(of: targetWeekday)
        }
        weeklySchedule.setGoal(dayGoal, for: targetWeekday)
        saveSchedule()
    }
    
    /// Applies an emergency goal change immediately, bypassing the next-day rule.
    /// **Why async?** Must update blocking status immediately after applying the change.
    /// - Parameter newGoal: The proposed goal configuration to apply now
    func applyEmergencyChange(_ newGoal: HealthGoal) async {
        var normalizedGoal = newGoal
        normalizedGoal.blockingStrategy = .all

        // Apply the changes immediately
        healthGoal.stepGoal = normalizedGoal.stepGoal
        healthGoal.activeEnergyGoal = normalizedGoal.activeEnergyGoal
        healthGoal.exerciseGoals = normalizedGoal.exerciseGoals
        healthGoal.timeBlockGoal = normalizedGoal.timeBlockGoal
        healthGoal.blockingStrategy = .all
        
        // Clear any pending changes since we're applying now
        healthGoal.pendingGoal = nil
        healthGoal.pendingGoalEffectiveDate = nil
        
        saveSchedule()
        
        // Update blocking status with the new goal
        scheduleTimeUnlockIfNeeded()
        await checkGoalStatus()
    }
    
    /// Cancels any pending goal changes for today.
    /// **Why expose this?** Allows users to change their mind before the change takes effect.
    func cancelPendingGoal() {
        healthGoal.pendingGoal = nil
        healthGoal.pendingGoalEffectiveDate = nil
        saveSchedule()
    }

    /// Returns whether easier goal edits should be deferred behind the pending-change flow.
    ///
    /// **Why fresh evaluation?** Goal edits are a high-impact path. We evaluate with
    /// current Health data at action time to avoid stale UI state bypassing the gate.
    func shouldDeferGoalEdits() async -> Bool {
        let latestSchedule = WeeklyGoalSchedule.load()
        let latestGoal = latestSchedule.goal(for: todayWeekday)
        return await GoalGatekeeper.shouldDeferEdits(
            goal: latestGoal,
            healthService: healthService
        )
    }

    // MARK: - Weekday-Aware Goal Editing

    /// Adds a goal for a specific weekday.
    ///
    /// **Why a separate overload?** When editing a future day's schedule, the operation
    /// should target that day's `HealthGoal` rather than today's. Future-day edits skip
    /// the deferral gate entirely because they don't affect the currently-active blocking.
    func addGoal(type: GoalType, target: Double, exerciseType: ExerciseType = .any, forWeekday weekday: Int) async {
        var dayGoal = weeklySchedule.goal(for: weekday)
        switch type {
        case .steps:
            dayGoal.stepGoal.isEnabled = true
            dayGoal.stepGoal.target = Int(target)
        case .activeEnergy:
            dayGoal.activeEnergyGoal.isEnabled = true
            dayGoal.activeEnergyGoal.target = Int(target)
        case .exercise:
            let newExerciseGoal = ExerciseGoal(
                isEnabled: true,
                targetMinutes: Int(target),
                exerciseType: exerciseType
            )
            dayGoal.exerciseGoals.append(newExerciseGoal)
        case .timeUnlock:
            dayGoal.timeBlockGoal.isEnabled = true
            dayGoal.timeBlockGoal.unlockTimeMinutes = Int(target)
        }
        weeklySchedule.setGoal(dayGoal, for: weekday)
        saveSchedule()

        // If editing today, reload live data and blocking
        if weekday == todayWeekday {
            isShowingAddGoal = false
            await loadGoals()
        }
    }

    /// Removes a goal for a specific weekday.
    func removeGoal(type: GoalType, exerciseGoalId: UUID? = nil, forWeekday weekday: Int) async {
        var dayGoal = weeklySchedule.goal(for: weekday)
        switch type {
        case .steps:
            dayGoal.stepGoal.isEnabled = false
        case .activeEnergy:
            dayGoal.activeEnergyGoal.isEnabled = false
        case .exercise:
            if let exerciseGoalId {
                dayGoal.exerciseGoals.removeAll { $0.id == exerciseGoalId }
            }
        case .timeUnlock:
            dayGoal.timeBlockGoal.isEnabled = false
        }
        weeklySchedule.setGoal(dayGoal, for: weekday)
        saveSchedule()
        scheduleTimeUnlockIfNeeded()

        if weekday == todayWeekday {
            await checkGoalStatus()
        }
    }

    /// Updates an existing goal for a specific weekday.
    func updateGoal(type: GoalType, target: Double, exerciseGoalId: UUID? = nil, exerciseType: ExerciseType = .any, forWeekday weekday: Int) async {
        var dayGoal = weeklySchedule.goal(for: weekday)
        switch type {
        case .steps:
            dayGoal.stepGoal.target = Int(target)
        case .activeEnergy:
            dayGoal.activeEnergyGoal.target = Int(target)
        case .exercise:
            if let exerciseGoalId,
               let index = dayGoal.exerciseGoals.firstIndex(where: { $0.id == exerciseGoalId }) {
                dayGoal.exerciseGoals[index].targetMinutes = Int(target)
                dayGoal.exerciseGoals[index].exerciseType = exerciseType
            }
        case .timeUnlock:
            dayGoal.timeBlockGoal.unlockTimeMinutes = Int(target)
        }
        weeklySchedule.setGoal(dayGoal, for: weekday)
        saveSchedule()
        scheduleTimeUnlockIfNeeded()

        if weekday == todayWeekday {
            await checkGoalStatus()
        }
    }

    // MARK: - Private Methods

    /// Persists the weekly schedule to App Group UserDefaults.
    ///
    /// **Why centralize?** Every mutation site calls this instead of `HealthGoal.save`.
    /// The schedule's save method also keeps the legacy `healthGoalData` key in sync
    /// for the DeviceActivityMonitor extension.
    private func saveSchedule() {
        for weekday in 1...7 {
            var dayGoal = weeklySchedule.goal(for: weekday)
            dayGoal.blockingStrategy = .all
            if var pending = dayGoal.pendingGoal {
                pending.blockingStrategy = .all
                dayGoal.pendingGoal = pending
            }
            weeklySchedule.setGoal(dayGoal, for: weekday)
        }
        WeeklyGoalSchedule.save(weeklySchedule)
    }
    
    /// Checks if a new day has started and resets the blocking state if necessary.
    /// **Why this matters?** At midnight, the step count resets to 0, but the app might
    /// still have apps unblocked from yesterday. This function detects the date change
    /// and re-engages the block to ensure users start each day locked until they meet their goal.
    /// **Design:** Synchronous date comparison with immediate state update. The subsequent
    /// async health fetch will trigger blocking via `checkGoalStatus()`.
    private func checkForNewDay() {
        let currentDayNumber = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        
        // If stored day differs from today, it's a new day
        if lastCheckedDayNumber != currentDayNumber {
            lastCheckedDayNumber = currentDayNumber
            // Re-derive todayWeekday so subsequent reads of `healthGoal` return the new day's config
            todayWeekday = Calendar.current.component(.weekday, from: Date())
            // Reset current steps to force a fresh check
            // The subsequent fetchDailySteps() will get today's actual (likely low) count
            // and checkGoalStatus() will re-engage blocking if needed
            currentSteps = 0
            currentActiveEnergy = 0
            currentExerciseMinutes = [:]
        }
    }
    
    /// Checks the user's progress toward their goal and updates app blocking accordingly.
    /// **Why this is the "gate"?** This is where health achievement (the "key") controls
    /// app access (the "lock"). If steps < goal, apps are blocked. If goal is met, access is granted.
    /// **Why try? instead of do-catch?** Blocking failures shouldn't prevent the UI from working.
    /// If the blocker service fails, we silently continue to display health data.
    /// - Returns: True if blocking state changed from blocked to unblocked (goal achieved)
    @discardableResult
    private func checkGoalStatus() async -> Bool {
        let shouldBlock = GoalBlockingEvaluator.shouldBlock(
            goal: healthGoal,
            snapshot: goalEvaluationSnapshot()
        )
        let wasBlocking = isBlocking
        
        if shouldBlock {
            try? await blockerService.updateShields(shouldBlock: true)
            isBlocking = true
        } else {
            try? await blockerService.updateShields(shouldBlock: false)
            isBlocking = false
        }
        
        // Return true if we transitioned from blocked to unblocked (goal achieved!)
        return wasBlocking && !isBlocking
    }
    
    /// Refreshes the daily step goal from UserDefaults.
    /// **Why read from UserDefaults directly?** The goal is set in SettingsView using
    /// @AppStorage. We read it here to ensure the dashboard always reflects the latest
    /// goal, even if the user changes it in Settings without restarting the app.
    private func refreshGoalFromStorage() {
        weeklySchedule = WeeklyGoalSchedule.load()
        todayWeekday = Calendar.current.component(.weekday, from: Date())
        
        // Apply pending changes for all days whose effective date has passed
        var didApplyAny = false
        for weekday in 1...7 {
            var dayGoal = weeklySchedule.goal(for: weekday)
            if dayGoal.blockingStrategy != .all {
                dayGoal.blockingStrategy = .all
                didApplyAny = true
            }
            if var pending = dayGoal.pendingGoal, pending.blockingStrategy != .all {
                pending.blockingStrategy = .all
                dayGoal.pendingGoal = pending
                didApplyAny = true
            }
            if dayGoal.applyPendingIfReady() {
                dayGoal.blockingStrategy = .all
                weeklySchedule.setGoal(dayGoal, for: weekday)
                didApplyAny = true
            } else {
                weeklySchedule.setGoal(dayGoal, for: weekday)
            }
        }
        if didApplyAny {
            saveSchedule()
        }
        
        scheduleTimeUnlockIfNeeded()
    }

    /// Schedules per-weekday unlock monitors for all days that have a time-block goal enabled.
    ///
    /// **Why schedule all 7 at once?** The OS needs to know the unlock time for every weekday
    /// ahead of time. We rebuild the full set on every save/refresh so removed or changed
    /// days are immediately reflected.
    private func scheduleTimeUnlockIfNeeded() {
        // Build entries for every day that has a time-block goal enabled
        var entries: [WeekdayUnlockEntry] = []
        for weekday in 1...7 {
            let dayGoal = weeklySchedule.goal(for: weekday)
            if dayGoal.timeBlockGoal.isEnabled {
                let minutes = dayGoal.timeBlockGoal.clampedUnlockMinutes
                if minutes > 0 {
                    entries.append(WeekdayUnlockEntry(weekday: weekday, unlockMinutes: minutes))
                }
            }
        }

        if entries.isEmpty {
            timeUnlockScheduler.cancelWeeklyUnlocks()
            timeUnlockScheduler.cancelDailyUnlock()
            return
        }

        do {
            try timeUnlockScheduler.scheduleWeeklyUnlocks(entries)
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

    private func fetchEnabledGoals() async throws -> (steps: Int, activeEnergy: Double, exerciseMinutes: [UUID: Int]) {
        var results = (steps: 0, activeEnergy: 0.0, exerciseMinutes: [UUID: Int]())
        var authorizationError: Error?
        
        await withTaskGroup(of: (GoalType, Double, UUID?, Error?).self) { group in
            if healthGoal.stepGoal.isEnabled {
                group.addTask {
                    do {
                        let steps = try await self.healthService.fetchDailySteps()
                        return (.steps, Double(steps), nil, nil)
                    } catch {
                        // Only propagate authorization errors, treat missing data as 0
                        if case HealthServiceError.authorizationDenied = error {
                            return (.steps, 0, nil, error)
                        }
                        return (.steps, 0, nil, nil)
                    }
                }
            }
            
            if healthGoal.activeEnergyGoal.isEnabled {
                group.addTask {
                    do {
                        let energy = try await self.healthService.fetchActiveEnergy()
                        return (.activeEnergy, energy, nil, nil)
                    } catch {
                        // Only propagate authorization errors, treat missing data as 0
                        if case HealthServiceError.authorizationDenied = error {
                            return (.activeEnergy, 0, nil, error)
                        }
                        return (.activeEnergy, 0, nil, nil)
                    }
                }
            }
            
            // Fetch data for each enabled exercise goal
            for exerciseGoal in healthGoal.exerciseGoals where exerciseGoal.isEnabled {
                let goalId = exerciseGoal.id
                let activityType = exerciseGoal.exerciseType.hkWorkoutActivityType
                group.addTask {
                    do {
                        let minutes = try await self.healthService.fetchExerciseMinutes(for: activityType)
                        return (.exercise, Double(minutes), goalId, nil)
                    } catch {
                        // Only propagate authorization errors, treat missing data as 0
                        if case HealthServiceError.authorizationDenied = error {
                            return (.exercise, 0, goalId, error)
                        }
                        return (.exercise, 0, goalId, nil)
                    }
                }
            }
            
            for await (type, value, goalId, error) in group {
                if let error = error {
                    authorizationError = error
                }
                
                switch type {
                case .steps:
                    results.steps = Int(value)
                case .activeEnergy:
                    results.activeEnergy = value
                case .exercise:
                    if let goalId {
                        results.exerciseMinutes[goalId] = Int(value)
                    }
                case .timeUnlock:
                    break // Time-based goals don't fetch from HealthKit
                }
            }
        }
        
        // Only throw if we encountered an actual authorization error
        if let authorizationError {
            throw authorizationError
        }
        
        return results
    }
}
