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
    
    /// Error message to display if an operation fails.
    var errorMessage: String?
    
    /// Indicates whether an error is currently being displayed.
    var hasError: Bool {
        errorMessage != nil
    }
    
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
    
    // MARK: - Initialization
    
    /// Creates a new DashboardViewModel with the specified health service.
    /// - Parameter healthService: The service to use for fetching health data.
    ///   Injected as a protocol to enable testing with mocks.
    init(healthService: any HealthServiceProtocol) {
        self.healthService = healthService
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
        isLoading = true
        errorMessage = nil
        
        defer { isLoading = false }
        
        do {
            currentSteps = try await healthService.fetchDailySteps()
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    /// Clears the current error message.
    func dismissError() {
        errorMessage = nil
    }
    
    // MARK: - Private Methods
    
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
