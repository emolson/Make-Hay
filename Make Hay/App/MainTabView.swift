//
//  MainTabView.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import os.log
import SwiftUI

/// The main tab-based navigation view for the app.
/// Contains Dashboard and Settings tabs.
///
/// **Why `@Environment` instead of the container?** Each dependency is injected via
/// a custom `EnvironmentKey`, so this view no longer couples to `AppDependencyContainer`.
/// Child views read their own dependencies from the environment — no manual threading.
///
/// **Why observe `scenePhase` here?** Background HealthKit delivery is best-effort and
/// can be throttled by iOS. If the last successful evaluation is older than the staleness
/// threshold when the app foregrounds, this root-level hook forces an immediate sync
/// regardless of which tab is visible — preventing the user from staying blocked due
/// to OS-level throttling.
struct MainTabView: View {

    private static let logger = AppLogger.logger(category: "MainTabView")

    /// Shared root tab selection state.
    /// **Why environment-backed?** This lets child views switch tabs without the app
    /// root manually threading bindings through every intermediate view.
    @Environment(\.appNavigation) private var appNavigation

    @Environment(\.permissionManager) private var permissionManager
    @Environment(\.backgroundHealthMonitor) private var backgroundHealthMonitor
    @Environment(\.dashboardViewModel) private var dashboardViewModel

    @Environment(\.scenePhase) private var scenePhase

    /// Debounce task for foreground refresh, preventing rapid foreground/background
    /// transitions from triggering multiple syncs.
    @State private var foregroundRefreshTask: Task<Void, Never>?
    
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
        .onChange(of: scenePhase) { _, newPhase in
            foregroundRefreshTask?.cancel()

            guard newPhase == .active else { return }

            foregroundRefreshTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }

                // Always refresh permissions — the user may have returned from
                // iOS Settings after toggling HealthKit or Screen Time access.
                await permissionManager.refresh()

                // Force a full sync only when background evaluation data is stale.
                // Non-stale cases are handled by the dashboard's own scenePhase
                // observer which does a lighter-weight goal reload.
                guard SharedStorage.isEvaluationStale else { return }

                do {
                    try await backgroundHealthMonitor.syncNow()
                } catch {
                    // Best-effort; dashboard's own refresh path will also attempt
                    // a load, and the Settings manual sync remains available.
                    let _ = error
                    Self.logger.warning("Foreground stale-data sync failed.")
                }

                // Reload dashboard state so UI reflects the fresh evaluation.
                await dashboardViewModel.loadGoals()
            }
        }
    }
}

#Preview {
    MainTabView()
}
