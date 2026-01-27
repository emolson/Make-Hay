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
    static var goalSteps: Color { Color("GoalSteps") }
    static var goalActiveEnergy: Color { Color("GoalActiveEnergy") }
    static var goalExercise: Color { Color("GoalExercise") }
    static var goalRingTrack: Color { Color("GoalRingTrack") }

    /// Status colors
    static var statusBlocked: Color { Color("StatusBlocked") }
    static var statusWarning: Color { Color("StatusWarning") }
}

// MARK: - Fonts

extension Font {
    /// Dashboard font tokens
    static var dashboardIcon: Font { .system(size: 32, weight: .regular, design: .default) }
    static var dashboardPrimaryValue: Font { .system(size: 36, weight: .bold, design: .rounded) }
    static var dashboardGoalMetIcon: Font { .system(size: 48, weight: .regular, design: .default) }
    static var dashboardErrorIcon: Font { .system(size: 50, weight: .regular, design: .default) }
}
