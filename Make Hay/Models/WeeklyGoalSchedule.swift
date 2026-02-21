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
/// On first load, if no schedule exists, the existing single `HealthGoal` is silently migrated
/// to all 7 days — zero friction for existing users.
struct WeeklyGoalSchedule: Codable, Sendable, Equatable {

    // MARK: - Properties

    /// Goal configuration for each weekday.
    /// Keys are `Calendar.weekday` values: 1 = Sunday, 2 = Monday, … 7 = Saturday.
    var days: [Int: HealthGoal]

    // MARK: - Initialization

    /// Creates a schedule with the provided per-day goals.
    /// Missing days default to a fresh `HealthGoal()`.
    init(days: [Int: HealthGoal] = [:]) {
        var filled: [Int: HealthGoal] = [:]
        for weekday in 1...7 {
            filled[weekday] = days[weekday] ?? HealthGoal()
        }
        self.days = filled
    }

    /// Creates a schedule where every day uses the same `HealthGoal`.
    /// **Why?** Used during migration from the legacy single-goal model.
    init(repeating goal: HealthGoal) {
        var filled: [Int: HealthGoal] = [:]
        for weekday in 1...7 {
            // Strip pending state — pending changes belong to the old model
            var clean = goal
            clean.pendingGoal = nil
            clean.pendingGoalEffectiveDate = nil
            filled[weekday] = clean
        }
        self.days = filled
    }

    // MARK: - Accessors

    /// Returns the `HealthGoal` for the given weekday (1–7).
    /// Falls back to a default `HealthGoal` if the key is somehow missing.
    func goal(for weekday: Int) -> HealthGoal {
        days[weekday] ?? HealthGoal()
    }

    /// Returns the `HealthGoal` for today based on the current calendar.
    func todayGoal(calendar: Calendar = .current) -> HealthGoal {
        let weekday = calendar.component(.weekday, from: Date())
        return goal(for: weekday)
    }

    /// Updates the goal for a specific weekday.
    mutating func setGoal(_ goal: HealthGoal, for weekday: Int) {
        days[weekday] = goal
    }

    // MARK: - Persistence

    static let storageKey: String = "weeklyGoalScheduleData"

    /// Loads the weekly schedule from App Group `UserDefaults`.
    ///
    /// **Migration strategy:** If no schedule exists, reads the legacy single `HealthGoal`
    /// and replicates it to all 7 days. This ensures existing users get a valid schedule
    /// on first launch after the update with zero onboarding friction.
    static func load(from defaults: UserDefaults = SharedStorage.appGroupDefaults) -> WeeklyGoalSchedule {
        // Try loading the weekly schedule
        if let dataString = defaults.string(forKey: storageKey),
           let data = dataString.data(using: .utf8),
           let schedule = try? JSONDecoder().decode(WeeklyGoalSchedule.self, from: data) {
            return schedule
        }

        // Migration: read the legacy single HealthGoal and replicate to all days
        let legacyGoal = HealthGoal.load(from: defaults)
        let migrated = WeeklyGoalSchedule(repeating: legacyGoal)
        save(migrated, to: defaults)
        return migrated
    }

    /// Saves the weekly schedule to App Group `UserDefaults`.
    static func save(_ schedule: WeeklyGoalSchedule, to defaults: UserDefaults = SharedStorage.appGroupDefaults) {
        if let encoded = encode(schedule) {
            defaults.set(encoded, forKey: storageKey)
        }
        // Also keep the legacy key in sync with today's goal so the
        // DeviceActivityMonitor extension can still read it.
        let todayWeekday = Calendar.current.component(.weekday, from: Date())
        let todayGoal = schedule.goal(for: todayWeekday)
        HealthGoal.save(todayGoal, to: defaults)
    }

    static func encode(_ schedule: WeeklyGoalSchedule) -> String? {
        guard let data = try? JSONEncoder().encode(schedule) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(from string: String) -> WeeklyGoalSchedule? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WeeklyGoalSchedule.self, from: data)
    }
}

// MARK: - Weekday Helpers

extension WeeklyGoalSchedule {

    /// Ordered weekday indices starting from the user's calendar first weekday.
    /// Returns `[Int]` of weekday values (1–7) in the order the user's locale expects.
    static func orderedWeekdays(calendar: Calendar = .current) -> [Int] {
        let first = calendar.firstWeekday // e.g. 1 (Sunday) in US, 2 (Monday) in EU
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    /// Short weekday symbol (e.g. "Mon") for a weekday index (1–7).
    static func shortName(for weekday: Int, calendar: Calendar = .current) -> String {
        calendar.shortWeekdaySymbols[weekday - 1]
    }

    /// Full weekday name (e.g. "Monday") for a weekday index (1–7).
    static func fullName(for weekday: Int, calendar: Calendar = .current) -> String {
        calendar.weekdaySymbols[weekday - 1]
    }
}
