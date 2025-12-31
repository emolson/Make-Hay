//
//  HealthGoal.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import Foundation

/// Model representing a user's daily health goal configuration.
struct HealthGoal: Codable, Sendable, Equatable {
    /// The target number of steps to achieve each day.
    var dailyStepTarget: Int = 10_000
}
