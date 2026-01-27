//
//  HealthGoal.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import Foundation
import HealthKit

/// Model representing a user's daily health goal configuration.
struct HealthGoal: Codable, Sendable, Equatable {
    /// The user's step goal configuration.
    var stepGoal: StepGoal = .init()
    /// The user's active energy goal configuration.
    var activeEnergyGoal: ActiveEnergyGoal = .init()
    /// The user's exercise goal configuration.
    var exerciseGoal: ExerciseGoal = .init()
    /// Strategy for determining when goals unlock apps.
    var blockingStrategy: BlockingStrategy = .any
}

/// Configuration for a steps goal.
struct StepGoal: Codable, Sendable, Equatable {
    var isEnabled: Bool = true
    var target: Int = 10_000
}

/// Configuration for an active energy (calories) goal.
struct ActiveEnergyGoal: Codable, Sendable, Equatable {
    var isEnabled: Bool = false
    var target: Int = 500
}

/// Configuration for an exercise minutes goal.
struct ExerciseGoal: Codable, Sendable, Equatable {
    var isEnabled: Bool = false
    var targetMinutes: Int = 30
    var exerciseType: ExerciseType = .any
}

/// Defines when apps unlock relative to enabled goals.
enum BlockingStrategy: String, Codable, CaseIterable, Sendable, Identifiable {
    case any
    case all
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .any:
            return String(localized: "Any Goal Reached")
        case .all:
            return String(localized: "All Goals Reached")
        }
    }
}

/// Supported exercise types for filtering workouts.
enum ExerciseType: String, Codable, CaseIterable, Sendable, Identifiable {
    case any
    case walking
    case running
    case cycling
    case hiit
    case strengthTraining
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .any:
            return String(localized: "Any")
        case .walking:
            return String(localized: "Walking")
        case .running:
            return String(localized: "Running")
        case .cycling:
            return String(localized: "Cycling")
        case .hiit:
            return String(localized: "HIIT")
        case .strengthTraining:
            return String(localized: "Strength")
        }
    }
    
    var iconName: String {
        switch self {
        case .any:
            return "figure.mixed.cardio"
        case .walking:
            return "figure.walk"
        case .running:
            return "figure.run"
        case .cycling:
            return "figure.outdoor.cycle"
        case .hiit:
            return "figure.highintensity.intervaltraining"
        case .strengthTraining:
            return "dumbbell.fill"
        }
    }
    
    var hkWorkoutActivityType: HKWorkoutActivityType? {
        switch self {
        case .any:
            return nil
        case .walking:
            return .walking
        case .running:
            return .running
        case .cycling:
            return .cycling
        case .hiit:
            return .highIntensityIntervalTraining
        case .strengthTraining:
            return .traditionalStrengthTraining
        }
    }
}

extension HealthGoal {
    static let storageKey: String = "healthGoalData"
    static let legacyStepKey: String = "dailyStepGoal"
    
    static func load(from defaults: UserDefaults = .standard) -> HealthGoal {
        if let dataString = defaults.string(forKey: storageKey),
           let data = dataString.data(using: .utf8),
           let goal = try? JSONDecoder().decode(HealthGoal.self, from: data) {
            return goal
        }
        
        let legacyStepGoal = defaults.integer(forKey: legacyStepKey)
        if legacyStepGoal > 0 {
            var migrated = HealthGoal()
            migrated.stepGoal.target = legacyStepGoal
            save(migrated, to: defaults)
            return migrated
        }
        
        return HealthGoal()
    }
    
    static func save(_ goal: HealthGoal, to defaults: UserDefaults = .standard) {
        if let encoded = encode(goal) {
            defaults.set(encoded, forKey: storageKey)
        }
    }
    
    static func encode(_ goal: HealthGoal) -> String? {
        guard let data = try? JSONEncoder().encode(goal) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    static func decode(from string: String) -> HealthGoal? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(HealthGoal.self, from: data)
    }
}
