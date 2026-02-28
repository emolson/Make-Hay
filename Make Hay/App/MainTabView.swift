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
    
    var body: some View {
        TabView {
            DashboardView()
            .tabItem {
                Label(
                    String(localized: "Dashboard"),
                    systemImage: "chart.bar.fill"
                )
            }
            .accessibilityIdentifier("dashboardTab")
            
            SettingsView()
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
