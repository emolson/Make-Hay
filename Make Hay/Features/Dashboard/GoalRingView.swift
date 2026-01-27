//
//  GoalRingView.swift
//  Make Hay
//
//  Created by Ethan Olson on 1/26/26.
//

import SwiftUI

/// A reusable activity ring for visualizing goal progress.
///
/// **Why a dedicated view?** Keeps the ring drawing logic isolated,
/// enabling multiple concentric rings without duplicating styling.
struct GoalRingView: View {
    let progress: Double
    let ringColor: Color
    let size: CGFloat
    let lineWidth: CGFloat
    let accessibilityId: String
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    Color.goalRingTrack,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [ringColor, ringColor.opacity(0.7), ringColor],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)
        }
        .frame(width: size, height: size)
        .accessibilityIdentifier(accessibilityId)
    }
}

// MARK: - Semantic Colors

extension Color {
    static var goalSteps: Color { .blue }
    static var goalActiveEnergy: Color { .orange }
    static var goalExercise: Color { .green }
    static var goalRingTrack: Color { .secondary.opacity(0.2) }
}

#Preview("Goal Ring") {
    GoalRingView(
        progress: 0.65,
        ringColor: .goalSteps,
        size: 220,
        lineWidth: 18,
        accessibilityId: "goalRing.preview"
    )
    .padding()
}
