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
    /// Very subtle success-tinted surface applied to the dashboard when the user's goals are met.
    /// **Why here?** Keeps the design system the single source of truth — views never own raw opacity formulas.
    static var surfaceUnlocked: Color { statusSuccess.opacity(0.05) }

    /// Onboarding-specific semantic colors.
    static var onboardingWelcome: Color { .yellow }
    static var onboardingButtonContent: Color { .white }
    static var onboardingSecondaryBackground: Color { Color(uiColor: .secondarySystemFill) }
    static var onboardingSecondaryContent: Color { Color(uiColor: .label) }
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
}
