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
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .steps:
            return String(localized: "Steps")
        case .activeEnergy:
            return String(localized: "Active Energy")
        case .exercise:
            return String(localized: "Exercise")
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
    
    var id: GoalType { type }
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
    var currentExerciseMinutes: Int = 0
    
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
    
    /// The last date the app checked for steps, stored as ISO8601 string.
    /// Used to detect when a new day has started and reset blocking accordingly.
    @ObservationIgnored
    @AppStorage("lastCheckedDate") private var lastCheckedDate: String = ""
    
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
                isMet: currentSteps >= healthGoal.stepGoal.target
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
                isMet: currentActiveEnergy >= Double(healthGoal.activeEnergyGoal.target)
            ))
        }
        
        if healthGoal.exerciseGoal.isEnabled {
            let target = Double(max(healthGoal.exerciseGoal.targetMinutes, 1))
            let current = Double(currentExerciseMinutes)
            let progress = min(current / target, 1.0)
            items.append(GoalProgress(
                type: .exercise,
                current: current,
                target: target,
                progress: progress,
                isMet: currentExerciseMinutes >= healthGoal.exerciseGoal.targetMinutes
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
            currentExerciseMinutes = 0
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
    }

    private func fetchEnabledGoals() async throws -> (steps: Int, activeEnergy: Double, exerciseMinutes: Int) {
        var results = (steps: 0, activeEnergy: 0.0, exerciseMinutes: 0)
        var authorizationError: Error?
        
        await withTaskGroup(of: (GoalType, Double, Error?).self) { group in
            if healthGoal.stepGoal.isEnabled {
                group.addTask {
                    do {
                        let steps = try await self.healthService.fetchDailySteps()
                        return (.steps, Double(steps), nil)
                    } catch {
                        // Only propagate authorization errors, treat missing data as 0
                        if case HealthServiceError.authorizationDenied = error {
                            return (.steps, 0, error)
                        }
                        return (.steps, 0, nil)
                    }
                }
            }
            
            if healthGoal.activeEnergyGoal.isEnabled {
                group.addTask {
                    do {
                        let energy = try await self.healthService.fetchActiveEnergy()
                        return (.activeEnergy, energy, nil)
                    } catch {
                        // Only propagate authorization errors, treat missing data as 0
                        if case HealthServiceError.authorizationDenied = error {
                            return (.activeEnergy, 0, error)
                        }
                        return (.activeEnergy, 0, nil)
                    }
                }
            }
            
            if healthGoal.exerciseGoal.isEnabled {
                let activityType = healthGoal.exerciseGoal.exerciseType.hkWorkoutActivityType
                group.addTask {
                    do {
                        let minutes = try await self.healthService.fetchExerciseMinutes(for: activityType)
                        return (.exercise, Double(minutes), nil)
                    } catch {
                        // Only propagate authorization errors, treat missing data as 0
                        if case HealthServiceError.authorizationDenied = error {
                            return (.exercise, 0, error)
                        }
                        return (.exercise, 0, nil)
                    }
                }
            }
            
            for await (type, value, error) in group {
                if let error = error {
                    authorizationError = error
                }
                
                switch type {
                case .steps:
                    results.steps = Int(value)
                case .activeEnergy:
                    results.activeEnergy = value
                case .exercise:
                    results.exerciseMinutes = Int(value)
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
