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
    /// Goal ring colors
    static var goalSteps: Color { Color(.goalSteps) }
    static var goalActiveEnergy: Color { Color(.goalActiveEnergy) }
    static var goalExercise: Color { Color(.goalExercise) }
    static var goalRingTrack: Color { Color(.goalRingTrack) }
    static var goalTimeUnlock: Color { .orange }

    /// Status colors
    static var statusBlocked: Color { Color(.statusBlocked) }
    static var statusWarning: Color { Color(.statusWarning) }
}

// MARK: - Fonts

extension Font {
    /// Dashboard font tokens
    static var dashboardIcon: Font { .system(size: 32, weight: .regular, design: .default) }
    static var dashboardPrimaryValue: Font { .system(size: 36, weight: .bold, design: .rounded) }
    static var dashboardGoalMetIcon: Font { .system(size: 48, weight: .regular, design: .default) }
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
}
