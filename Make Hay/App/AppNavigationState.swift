//
//  AppNavigationState.swift
//  Make Hay
//
//  Created by GitHub Copilot on 4/8/26.
//

import Foundation

/// High-level tabs available from the app root.
///
/// **Why an enum?** Keeps cross-tab navigation type-safe and avoids leaking
/// raw integer tags across the view hierarchy.
enum AppTab: Hashable {
    case dashboard
    case settings
}

/// Shared app-level navigation state for root tab selection.
///
/// **Why a dedicated observable type?** Views in different tabs occasionally need
/// to route the user to another tab, such as the Dashboard permission banner taking
/// the user to the in-app Settings screen. Centralising tab selection here keeps
/// that flow declarative and avoids URL-based workarounds.
@Observable
@MainActor
final class AppNavigationState {
    var selectedTab: AppTab = .dashboard
}