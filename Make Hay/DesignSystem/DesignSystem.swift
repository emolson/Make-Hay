//
//  DesignSystem.swift
//  Make Hay
//
//  Created by Ethan Olson on 1/27/26.
//

import SwiftUI

/// Centralized design system tokens for colors and fonts.
enum DesignSystem {}

// MARK: - Colors

extension Color {
    /// Goal progress colors
    static var goalSteps: Color { Color(.goalSteps) }
    static var goalActiveEnergy: Color { Color(.goalActiveEnergy) }
    static var goalExercise: Color { Color(.goalExercise) }
    static var goalBarTrack: Color { Color(.goalRingTrack) }
    static var goalTimeUnlock: Color { .orange }

    /// Status colors — semantic tokens for feedback states.
    /// **Why tokens?** Centralizing colors here ensures every view stays
    /// consistent and a single change propagates app-wide.
    static var statusBlocked: Color { Color(.statusBlocked) }
    static var statusWarning: Color { Color(.statusWarning) }
    static var statusSuccess: Color { .green }
    static var statusInfo: Color { .blue }
    static var statusError: Color { .red }
    static var statusPermissionPending: Color { .purple }
    static var statusPermissionMissing: Color { .orange }

    /// Surface / background colors for grouped card layouts.
    static var surfaceGrouped: Color { Color(uiColor: .systemGroupedBackground) }
    static var surfaceCard: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    /// Onboarding-specific semantic colors.
    static var onboardingWelcome: Color { .yellow }
    static var onboardingButtonContent: Color { .white }
}

// MARK: - Fonts

extension Font {
    /// Dashboard font tokens
    static var dashboardIcon: Font { .system(size: 32, weight: .regular, design: .default) }
    static var dashboardErrorIcon: Font { .system(size: 50, weight: .regular, design: .default) }
}

// MARK: - Date Helpers

extension Date {
    /// Returns local midnight for tomorrow using the current calendar.
    ///
    /// **Why centralize this?** Goal and blocked-app pending flows must use identical
    /// scheduling semantics to avoid user-visible mismatches.
    static func localMidnightTomorrow(from date: Date = Date(), calendar: Calendar = .current) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        return calendar.startOfDay(for: tomorrow)
    }

    /// Returns the next midnight at which the given weekday occurs.
    ///
    /// If `weekday` matches the current day, returns midnight 7 days from now (i.e. next
    /// week's same day) so that a pending change on the current day always defers forward.
    ///
    /// **Why 7 days for today?** Edits to today's schedule that make it easier should not
    /// take effect until the *next* occurrence of that day (one week later), matching the
    /// existing "Next-Day Effect" philosophy extended to the weekly model.
    ///
    /// - Parameters:
    ///   - weekday: A `Calendar.weekday` value (1 = Sunday … 7 = Saturday).
    ///   - date: The reference date (defaults to now).
    ///   - calendar: The calendar to use (defaults to `.current`).
    /// - Returns: The `Date` representing midnight of the next occurrence of `weekday`.
    static func nextOccurrence(
        of weekday: Int,
        after date: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let todayWeekday = calendar.component(.weekday, from: date)
        let daysUntil: Int
        if weekday == todayWeekday {
            daysUntil = 7
        } else {
            daysUntil = (weekday - todayWeekday + 7) % 7
        }
        let target = calendar.date(byAdding: .day, value: daysUntil, to: date) ?? date
        return calendar.startOfDay(for: target)
    }
}
