//
//  MainTabView.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import SwiftUI

/// The main tab-based navigation view for the app.
/// Contains Dashboard and Settings tabs.
///
/// **Why `@Environment` instead of the container?** Each dependency is injected via
/// a custom `EnvironmentKey`, so this view no longer couples to `AppDependencyContainer`.
/// Child views read their own dependencies from the environment — no manual threading.
struct MainTabView: View {

    /// Shared root tab selection state.
    /// **Why environment-backed?** This lets child views switch tabs without the app
    /// root manually threading bindings through every intermediate view.
    @Environment(\.appNavigation) private var appNavigation
    
    var body: some View {
        TabView(selection: Binding(
            get: { appNavigation.selectedTab },
            set: { appNavigation.selectedTab = $0 }
        )) {
            DashboardView()
            .tag(AppTab.dashboard)
            .tabItem {
                Label(
                    String(localized: "Dashboard"),
                    systemImage: "chart.bar.fill"
                )
            }
            .accessibilityIdentifier("dashboardTab")
            
            SettingsView()
                .tag(AppTab.settings)
                .tabItem {
                    Label(
                        String(localized: "Settings"),
                        systemImage: "gearshape.fill"
                    )
                }
                .accessibilityIdentifier("settingsTab")
        }
    }
}

#Preview {
    MainTabView()
}
