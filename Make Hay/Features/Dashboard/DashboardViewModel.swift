//
//  DashboardViewModel.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import SwiftUI

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
    
    /// The user's daily step goal, read from UserDefaults via AppStorage key.
    /// This is refreshed each time the view appears to stay in sync with Settings.
    var dailyStepGoal: Int = 10_000
    
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
    
    /// Calculates the user's progress toward their daily step goal.
    /// Returns a value between 0.0 and 1.0 (capped at 1.0 even if goal exceeded).
    var progress: Double {
        guard dailyStepGoal > 0 else { return 0.0 }
        return min(Double(currentSteps) / Double(dailyStepGoal), 1.0)
    }
    
    /// Indicates whether the user has met or exceeded their daily step goal.
    var isGoalMet: Bool {
        currentSteps >= dailyStepGoal
    }
    
    // MARK: - Dependencies
    
    private let healthService: any HealthServiceProtocol
    private let blockerService: any BlockerServiceProtocol
    
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
    
    /// Fetches the current day's step count from HealthKit.
    /// Updates `currentSteps`, `isLoading`, and `errorMessage` accordingly.
    /// Note: This assumes authorization has already been granted.
    func loadSteps() async {
        // Check if it's a new day before loading steps
        checkForNewDay()
        
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            currentSteps = try await healthService.fetchDailySteps()
            // Check and update blocking status after loading steps
            await checkGoalStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    /// Requests HealthKit authorization and then loads steps.
    /// Use this when the user taps retry after an authorization error.
    func requestAuthorizationAndLoad() async {
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            try await healthService.requestAuthorization()
            currentSteps = try await healthService.fetchDailySteps()
            // Check and update blocking status after loading steps
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
        let todayString = ISO8601DateFormatter().string(from: today)
        
        // If stored date differs from today, it's a new day
        if lastCheckedDate != todayString {
            lastCheckedDate = todayString
            // Reset current steps to force a fresh check
            // The subsequent fetchDailySteps() will get today's actual (likely low) count
            // and checkGoalStatus() will re-engage blocking if needed
            currentSteps = 0
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
        let shouldBlock = currentSteps < dailyStepGoal
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
        dailyStepGoal = UserDefaults.standard.integer(forKey: "dailyStepGoal")
        // If no value has been set, use the default
        if dailyStepGoal == 0 {
            dailyStepGoal = 10_000
        }
    }
}
