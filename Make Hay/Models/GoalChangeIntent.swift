//
//  GoalChangeIntent.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/3/26.
//

import Foundation

/// Represents the user's intent when modifying their health goals.
/// Used to determine whether changes should apply immediately or be scheduled.
enum GoalChangeIntent: Sendable {
    /// The user is making goals easier (lowering targets or disabling goals).
    case easier
    /// The user is making goals harder (raising targets or enabling new goals).
    case harder
    /// The changes are neutral (no meaningful difficulty change).
    case neutral
    
    /// Determines the intent by comparing original and proposed goal configurations.
    /// **Why this logic?** Making goals easier removes the immediate incentive to cheat.
    /// If any target decreases or any goal is disabled, the entire change is "easier."
    ///
    /// - Parameters:
    ///   - original: The current goal configuration
    ///   - proposed: The proposed new goal configuration
    /// - Returns: The determined intent based on the changes
    static func determine(original: HealthGoal, proposed: HealthGoal) -> GoalChangeIntent {
        var hasEasier = false
        var hasHarder = false
        
        // Check step goal
        if original.stepGoal.isEnabled && proposed.stepGoal.isEnabled {
            if proposed.stepGoal.target < original.stepGoal.target {
                hasEasier = true
            } else if proposed.stepGoal.target > original.stepGoal.target {
                hasHarder = true
            }
        } else if original.stepGoal.isEnabled && !proposed.stepGoal.isEnabled {
            // Disabling a goal is easier
            hasEasier = true
        } else if !original.stepGoal.isEnabled && proposed.stepGoal.isEnabled {
            // Enabling a new goal is harder
            hasHarder = true
        }
        
        // Check active energy goal
        if original.activeEnergyGoal.isEnabled && proposed.activeEnergyGoal.isEnabled {
            if proposed.activeEnergyGoal.target < original.activeEnergyGoal.target {
                hasEasier = true
            } else if proposed.activeEnergyGoal.target > original.activeEnergyGoal.target {
                hasHarder = true
            }
        } else if original.activeEnergyGoal.isEnabled && !proposed.activeEnergyGoal.isEnabled {
            hasEasier = true
        } else if !original.activeEnergyGoal.isEnabled && proposed.activeEnergyGoal.isEnabled {
            hasHarder = true
        }
        
        // Check exercise goals
        // Compare matching goals by ID
        for proposedExercise in proposed.exerciseGoals where proposedExercise.isEnabled {
            if let originalExercise = original.exerciseGoals.first(where: { $0.id == proposedExercise.id }) {
                if originalExercise.isEnabled {
                    if proposedExercise.targetMinutes < originalExercise.targetMinutes {
                        hasEasier = true
                    } else if proposedExercise.targetMinutes > originalExercise.targetMinutes {
                        hasHarder = true
                    }
                } else {
                    // Re-enabling a goal is harder
                    hasHarder = true
                }
            } else {
                // New exercise goal is harder
                hasHarder = true
            }
        }
        
        // Check for removed exercise goals (easier)
        for originalExercise in original.exerciseGoals where originalExercise.isEnabled {
            let stillExists = proposed.exerciseGoals.contains { $0.id == originalExercise.id && $0.isEnabled }
            if !stillExists {
                hasEasier = true
            }
        }
        
        // Check time block goal
        if original.timeBlockGoal.isEnabled && proposed.timeBlockGoal.isEnabled {
            // Earlier unlock time is easier (lower target minutes)
            if proposed.timeBlockGoal.unlockTimeMinutes < original.timeBlockGoal.unlockTimeMinutes {
                hasEasier = true
            } else if proposed.timeBlockGoal.unlockTimeMinutes > original.timeBlockGoal.unlockTimeMinutes {
                hasHarder = true
            }
        } else if original.timeBlockGoal.isEnabled && !proposed.timeBlockGoal.isEnabled {
            hasEasier = true
        } else if !original.timeBlockGoal.isEnabled && proposed.timeBlockGoal.isEnabled {
            hasHarder = true
        }
        
        // Priority: If any change makes it easier, classify as easier
        // This prevents users from sneaking an easier change alongside a harder one
        if hasEasier {
            return .easier
        } else if hasHarder {
            return .harder
        } else {
            return .neutral
        }
    }
}
