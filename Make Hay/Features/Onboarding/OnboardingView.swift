//
//  OnboardingView.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import SwiftUI

/// Placeholder onboarding view that will guide users through permission setup.
/// Full implementation will be added in Story 3.
struct OnboardingView: View {
    /// Binding to track whether onboarding has been completed.
    @Binding var hasCompletedOnboarding: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "sun.max.fill")
                .font(.system(size: 80))
                .foregroundStyle(.yellow)
                .accessibilityIdentifier("onboardingIcon")
            
            Text(String(localized: "Welcome to Make Hay"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(String(localized: "Earn your screen time by hitting your health goals."))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
            
            Button {
                hasCompletedOnboarding = true
            } label: {
                Text(String(localized: "Get Started"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
            .accessibilityIdentifier("getStartedButton")
            
            Spacer()
                .frame(height: 40)
        }
        .padding()
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .environmentObject(AppDependencyContainer.preview())
}
