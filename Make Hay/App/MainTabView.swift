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
///
/// **Why observe `scenePhase` here?** This root-level hook always refreshes permission
/// state on foreground resume, but only triggers a dashboard health sync when the
/// Dashboard tab is visible. That keeps Settings responsive and avoids off-screen
/// sync churn while still refreshing the data users are actively looking at.
struct MainTabView: View {

    private static let minimumForegroundSyncInterval: TimeInterval = 5
    private static let traceCategory = "MainTabView"

    /// Shared root tab selection state.
    /// **Why environment-backed?** This lets child views switch tabs without the app
    /// root manually threading bindings through every intermediate view.
    @Environment(\.appNavigation) private var appNavigation

    @Environment(\.permissionManager) private var permissionManager
    @Environment(\.dashboardViewModel) private var dashboardViewModel

    @Environment(\.scenePhase) private var scenePhase

    /// Debounce task for foreground refresh, preventing rapid foreground/background
    /// transitions from triggering multiple syncs.
    @State private var foregroundRefreshTask: Task<Void, Never>?

    /// Timestamp of the last foreground sync attempt.
    @State private var lastForegroundSyncDate: Date?
    
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
            AppLogger.trace(
                category: Self.traceCategory,
                message: "scenePhase changed to \(String(describing: newPhase))."
            )

            foregroundRefreshTask?.cancel()

            guard newPhase == .active else { return }

            let refreshID = UUID().uuidString
            foregroundRefreshTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else {
                    AppLogger.trace(
                        category: Self.traceCategory,
                        message: "Foreground refresh cancelled during debounce. id=\(refreshID)"
                    )
                    return
                }

                let currentTab = appNavigation.selectedTab
                let currentTabName = currentTab == .dashboard ? "dashboard" : "settings"

                AppLogger.trace(
                    category: Self.traceCategory,
                    message: "Foreground refresh running. id=\(refreshID)"
                )

                // Always refresh permissions — the user may have returned from
                // iOS Settings after toggling HealthKit or Screen Time access.
                await permissionManager.refresh(reason: "mainTab.scenePhase.active.\(currentTabName)")

                // The Settings screen only needs fresh permission state on resume.
                // Full health sync is deferred to the Dashboard or explicit manual refresh.
                guard currentTab == .dashboard else {
                    AppLogger.trace(
                        category: Self.traceCategory,
                        message: "Skipping foreground health sync because the selected tab is settings. id=\(refreshID)"
                    )
                    return
                }

                if let lastForegroundSyncDate,
                   Date().timeIntervalSince(lastForegroundSyncDate) < Self.minimumForegroundSyncInterval {
                    AppLogger.trace(
                        category: Self.traceCategory,
                        message: "Suppressing foreground health sync because cooldown is active. id=\(refreshID)"
                    )
                    return
                }

                lastForegroundSyncDate = Date()

                // Unified sync: loadGoals() internally calls syncNow() which
                // fetches health data, evaluates goals, updates shields, and
                // persists the snapshot — all in one pipeline.
                await dashboardViewModel.loadGoals(reason: "mainTab.scenePhase.active.dashboard")

                AppLogger.trace(
                    category: Self.traceCategory,
                    message: "Foreground health sync finished. id=\(refreshID)"
                )
            }
        }
    }
}

#Preview {
    MainTabView()
}
