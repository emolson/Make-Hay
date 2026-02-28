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
    /// **Why not `@State`?** The container is no longer `@Observable` — it's a plain
    /// factory/lifecycle owner. We keep a strong reference so services live for the
    /// app's lifetime; individual services are injected into the environment below.
    private let container = AppDependencyContainer()
    
    /// Persisted flag indicating whether onboarding has been completed.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView(
                    hasCompletedOnboarding: $hasCompletedOnboarding
                )
            }
        }
        .environment(\.healthService, container.healthService)
        .environment(\.blockerService, container.blockerService)
        .environment(\.dashboardViewModel, container.dashboardViewModel)
    }
}
