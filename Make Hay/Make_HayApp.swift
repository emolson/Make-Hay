//
//  Make_HayApp.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import SwiftUI

@main
struct Make_HayApp: App {
    /// Dependency container holding all app services.
    @State private var container = AppDependencyContainer()
    
    /// Persisted flag indicating whether onboarding has been completed.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                MainTabView()
                    .environment(container)
            } else {
                OnboardingView(
                    hasCompletedOnboarding: $hasCompletedOnboarding,
                    healthService: container.healthService,
                    blockerService: container.blockerService
                )
                .environment(container)
            }
        }
    }
}
