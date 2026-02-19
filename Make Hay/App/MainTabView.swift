//
//  MainTabView.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import SwiftUI

/// The main tab-based navigation view for the app.
/// Contains Dashboard and Settings tabs.
struct MainTabView: View {
    @EnvironmentObject private var container: AppDependencyContainer
    
    var body: some View {
        TabView {
            DashboardView(
                viewModel: container.dashboardViewModel
            )
            .tabItem {
                Label(
                    String(localized: "Dashboard"),
                    systemImage: "chart.bar.fill"
                )
            }
            .accessibilityIdentifier("dashboardTab")
            
            SettingsView(
                healthService: container.healthService,
                blockerService: container.blockerService,
                goalStatusProvider: container.dashboardViewModel
            )
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
        .environmentObject(AppDependencyContainer.preview())
}
