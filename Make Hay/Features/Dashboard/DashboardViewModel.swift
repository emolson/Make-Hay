//
//  DashboardViewModel.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import SwiftUI
import HealthKit

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
final class DashboardViewModel {
    
    // MARK: - State
    
    /// The current step count fetched from HealthKit.
    var currentSteps: Int = 0
    
    /// The current active energy fetched from HealthKit (kilocalories).
    var currentActiveEnergy: Double = 0
    
    /// The current exercise minutes fetched from HealthKit.
    /// Stores exercise minutes by goal ID.
    var currentExerciseMinutes: [UUID: Int] = [:]
    
    /// The user's goal configuration, refreshed from storage on appearance.
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
    
    /// Controls presentation of the Add Goal sheet.
    var isShowingAddGoal: Bool = false
    
    /// The last date the app checked for steps, stored as ISO8601 string.
    /// Used to detect when a new day has started and reset blocking accordingly.
    @ObservationIgnored
    @AppStorage("lastCheckedDate") private var lastCheckedDate: String = ""

    /// Task used to unlock apps when a time-based goal becomes active.
    private var timeUnlockTask: Task<Void, Never>?
    
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
        let progresses = goalProgresses
        guard !progresses.isEmpty else { return true }
        
        switch healthGoal.blockingStrategy {
        case .any:
            return progresses.contains { $0.isMet }
        case .all:
            return progresses.allSatisfy { $0.isMet }
        }
    }
    
    // MARK: - Dependencies
    
    private let healthService: any HealthServiceProtocol
    private let blockerService: any BlockerServiceProtocol
    
    /// Static ISO8601 formatter for date comparisons.
    /// **Why static?** DateFormatters are expensive to create. A static instance
    /// is created once and reused across all instances and calls.
    private static let dateFormatter = ISO8601DateFormatter()
    
    // MARK: - Initialization
    
    /// Creates a new DashboardViewModel with the specified services.
    /// - Parameters:
    ///   - healthService: The service to use for fetching health data.
    ///   - blockerService: The service to use for managing app blocking.
    ///   Both are injected as protocols to enable testing with mocks.
    init(healthService: any HealthServiceProtocol, blockerService: any BlockerServiceProtocol) {
        self.healthService = healthService
        self.blockerService = blockerService
        refreshGoalFromStorage()
    }
    
    // MARK: - Actions
    
    /// Called when the view appears. Ensures authorization and triggers initial data load.
    /// **Why request authorization here?** HealthKit requires explicit authorization before
    /// queries can succeed. Requesting authorization when already granted is a no-op.
    func onAppear() async {
        refreshGoalFromStorage()
        await requestAuthorizationAndLoad()
    }
    
    /// Fetches the current day's health metrics from HealthKit.
    /// Updates current values, loading state, and error state.
    /// Note: This assumes authorization has already been granted.
    func loadGoals() async {
        // Check if it's a new day before loading steps
        checkForNewDay()
        
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            refreshGoalFromStorage()
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
        
        HealthGoal.save(healthGoal)
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
        
        HealthGoal.save(healthGoal)
        
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
    func updateGoal(type: GoalType, target: Double, exerciseGoalId: UUID? = nil, exerciseType: ExerciseType = .any) {
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
        
        HealthGoal.save(healthGoal)
    }
    
    /// Updates the blocking strategy.
    /// **Why async?** After changing the strategy, we need to recalculate whether
    /// apps should be blocked based on the new logic (any vs all).
    func updateBlockingStrategy(_ strategy: BlockingStrategy) async {
        healthGoal.blockingStrategy = strategy
        HealthGoal.save(healthGoal)
        await checkGoalStatus()
    }
    
    // MARK: - Private Methods
    
    /// Checks if a new day has started and resets the blocking state if necessary.
    /// **Why this matters?** At midnight, the step count resets to 0, but the app might
    /// still have apps unblocked from yesterday. This function detects the date change
    /// and re-engages the block to ensure users start each day locked until they meet their goal.
    /// **Design:** Synchronous date comparison with immediate state update. The subsequent
    /// async health fetch will trigger blocking via `checkGoalStatus()`.
    private func checkForNewDay() {
        let today = Calendar.current.startOfDay(for: Date())
        let todayString = Self.dateFormatter.string(from: today)
        
        // If stored date differs from today, it's a new day
        if lastCheckedDate != todayString {
            lastCheckedDate = todayString
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
        let hasEnabledGoals = !goalProgresses.isEmpty
        let shouldBlock = hasEnabledGoals ? !isGoalMet : false
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
        healthGoal = HealthGoal.load()
        scheduleTimeUnlockIfNeeded()
    }

    private func scheduleTimeUnlockIfNeeded() {
        timeUnlockTask?.cancel()

        guard healthGoal.timeBlockGoal.isEnabled else { return }

        let now = Date()
        let unlockDate = healthGoal.timeBlockGoal.unlockDate(on: now)
        guard unlockDate > now else { return }

        let interval = unlockDate.timeIntervalSince(now)
        timeUnlockTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return
            }

            guard !Task.isCancelled, let self else { return }
            await self.checkGoalStatus()
        }
    }

    private func currentMinutesSinceMidnight(date: Date = Date()) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
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
