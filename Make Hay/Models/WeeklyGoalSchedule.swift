//
//  WeeklyGoalSchedule.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/21/26.
//

import Foundation

/// A weekly goal schedule mapping each weekday to an independent `HealthGoal`.
///
/// **Why a full `HealthGoal` per day?** Reuses all existing goal evaluation, pending-change
/// gating, and blocking logic without introducing a new abstraction layer. Each day can
/// independently configure steps, active energy, exercise, time-unlock, and blocking strategy.
///
/// **Storage:** JSON-encoded in App Group `UserDefaults` under `"weeklyGoalScheduleData"`.
struct WeeklyGoalSchedule: Codable, Sendable, Equatable {

    // MARK: - Properties

    /// Goal configuration for each weekday.
    /// Keys are `Calendar.weekday` values: 1 = Sunday, 2 = Monday, … 7 = Saturday.
    var days: [Int: HealthGoal]

    // MARK: - Initialization

    /// Creates a schedule with the provided per-day goals.
    /// Missing days default to a fresh `HealthGoal()`.
    nonisolated init(days: [Int: HealthGoal] = [:]) {
        var filled: [Int: HealthGoal] = [:]
        for weekday in 1...7 {
            filled[weekday] = days[weekday] ?? HealthGoal()
        }
        self.days = filled
    }

    // MARK: - Accessors

    /// Returns the `HealthGoal` for the given weekday (1–7).
    /// Falls back to a default `HealthGoal` if the key is somehow missing.
    nonisolated func goal(for weekday: Int) -> HealthGoal {
        days[weekday] ?? HealthGoal()
    }

    /// Returns the `HealthGoal` for today based on the current calendar.
    nonisolated func todayGoal(calendar: Calendar = .current) -> HealthGoal {
        let weekday = calendar.component(.weekday, from: Date())
        return goal(for: weekday)
    }

    /// Updates the goal for a specific weekday.
    nonisolated mutating func setGoal(_ goal: HealthGoal, for weekday: Int) {
        days[weekday] = goal
    }

    // MARK: - Persistence

    nonisolated static let storageKey: String = "weeklyGoalScheduleData"

    private enum CodingKeys: String, CodingKey {
        case days
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(days: try container.decodeIfPresent([Int: HealthGoal].self, forKey: .days) ?? [:])
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(days, forKey: .days)
    }

    /// Loads the weekly schedule from App Group `UserDefaults`.
    nonisolated static func load(from defaults: UserDefaults = SharedStorage.appGroupDefaults) -> WeeklyGoalSchedule {
        if let dataString = defaults.string(forKey: storageKey),
           let data = dataString.data(using: .utf8),
           let schedule = try? JSONDecoder().decode(WeeklyGoalSchedule.self, from: data) {
            return schedule
        }

        return WeeklyGoalSchedule()
    }

    /// Saves the weekly schedule to App Group `UserDefaults`.
    nonisolated static func save(_ schedule: WeeklyGoalSchedule, to defaults: UserDefaults = SharedStorage.appGroupDefaults) {
        if let encoded = encode(schedule) {
            defaults.set(encoded, forKey: storageKey)
        }
    }

    nonisolated static func encode(_ schedule: WeeklyGoalSchedule) -> String? {
        guard let data = try? JSONEncoder().encode(schedule) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated static func decode(from string: String) -> WeeklyGoalSchedule? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WeeklyGoalSchedule.self, from: data)
    }
}

// MARK: - Weekday Helpers

extension WeeklyGoalSchedule {

    /// Ordered weekday indices starting from the user's calendar first weekday.
    /// Returns `[Int]` of weekday values (1–7) in the order the user's locale expects.
    nonisolated static func orderedWeekdays(calendar: Calendar = .current) -> [Int] {
        let first = calendar.firstWeekday // e.g. 1 (Sunday) in US, 2 (Monday) in EU
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    /// Short weekday symbol (e.g. "Mon") for a weekday index (1–7).
    nonisolated static func shortName(for weekday: Int, calendar: Calendar = .current) -> String {
        calendar.shortWeekdaySymbols[weekday - 1]
    }

    /// Full weekday name (e.g. "Monday") for a weekday index (1–7).
    nonisolated static func fullName(for weekday: Int, calendar: Calendar = .current) -> String {
        calendar.weekdaySymbols[weekday - 1]
    }
}
