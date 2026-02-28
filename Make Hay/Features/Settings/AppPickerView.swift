//
//  AppPickerView.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import FamilyControls
import SwiftUI

/// A view that presents the Family Activity Picker for selecting apps to block.
///
/// **Why a separate view?** Encapsulates picker presentation and layout,
/// keeping `SettingsView` focused on section arrangement. All business logic
/// (persistence, shield updates, haptic feedback) lives in `AppPickerViewModel`.
///
/// **Note:** The `.familyActivityPicker` modifier does NOT render in the iOS Simulator.
/// You must test this feature on a physical device with Family Controls capability enabled.
struct AppPickerView: View {

    /// Identity token for the currently injected dependencies.
    ///
    /// **Why this exists:** If previews/tests swap environment services at runtime,
    /// the view should rebuild its ViewModel so state stays aligned with the
    /// latest dependency graph instead of retaining stale service references.
    private struct DependencyIdentity: Equatable {
        let blockerService: ObjectIdentifier
        let healthService: ObjectIdentifier
        let dashboardViewModel: ObjectIdentifier
    }

    // MARK: - Dependencies

    /// Services read from the environment — no init params needed.
    /// **Why `@Environment`?** Decouples this view from its parent (`SettingsView`),
    /// eliminates service-threading boilerplate, and makes previews zero-config.
    @Environment(\.blockerService) private var blockerService
    @Environment(\.healthService) private var healthService
    @Environment(\.dashboardViewModel) private var dashboardViewModel

    // MARK: - ViewModel

    /// Owned by this view via `@State` so the edit session survives SwiftUI re-renders.
    /// **Why optional?** Services aren't available in `init` when using `@Environment`,
    /// so the VM is created lazily in `.task`. The one-frame `nil` state is imperceptible.
    @State private var viewModel: AppPickerViewModel?

    /// Stable identity for environment-injected dependencies.
    ///
    /// **Why cast to `AnyObject`?** Service protocols are actor-based references.
    /// Using `ObjectIdentifier` lets `.task(id:)` detect reference changes cleanly.
    private var dependencyIdentity: DependencyIdentity {
        DependencyIdentity(
            blockerService: ObjectIdentifier(blockerService as AnyObject),
            healthService: ObjectIdentifier(healthService as AnyObject),
            dashboardViewModel: ObjectIdentifier(dashboardViewModel)
        )
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let viewModel {
                pickerContent(viewModel: viewModel)
            } else {
                ProgressView()
            }
        }
        .task(id: dependencyIdentity) {
            let nextViewModel = AppPickerViewModel(
                blockerService: blockerService,
                healthService: healthService,
                goalStatusProvider: dashboardViewModel
            )
            viewModel = nextViewModel
            await nextViewModel.loadCurrentSelection()
        }
    }

    // MARK: - Picker Content

    /// Main picker content, extracted so the `viewModel` binding is non-optional.
    @ViewBuilder
    private func pickerContent(viewModel: AppPickerViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            selectionSummary(viewModel: viewModel)
            pickerButton(viewModel: viewModel)
        }
        .familyActivityPicker(
            isPresented: Binding(
                get: { viewModel.isPickerPresented },
                set: { viewModel.isPickerPresented = $0 }
            ),
            selection: Binding(
                get: { viewModel.draftSelection },
                set: { viewModel.draftSelection = $0 }
            )
        )
        .onChange(of: viewModel.isPickerPresented) { _, isPresented in
            if !isPresented {
                viewModel.pickerDismissed()
            }
        }
        .alert(
            String(localized: "Error"),
            isPresented: Binding(
                get: { viewModel.showError },
                set: { viewModel.showError = $0 }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showingPendingConfirmation },
            set: { viewModel.showingPendingConfirmation = $0 }
        )) {
            PendingGoalChangeView(context: .blockedAppsChange) {
                Task {
                    await viewModel.schedulePendingSelection()
                }
            } onEmergencyUnlock: {
                Task {
                    await viewModel.applyEmergencySelectionChange()
                }
            }
        }
    }

    // MARK: - Subviews

    /// Displays a summary of the committed (persisted) selection.
    @ViewBuilder
    private func selectionSummary(viewModel: AppPickerViewModel) -> some View {
        let appCount = viewModel.persistedSelection.applicationTokens.count
        let categoryCount = viewModel.persistedSelection.categoryTokens.count

        if appCount == 0 && categoryCount == 0 {
            HStack {
                Image(systemName: "app.badge")
                    .foregroundStyle(.secondary)
                Text(String(localized: "No apps selected"))
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("noAppsSelectedLabel")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if appCount > 0 {
                    Label(
                        String(localized: "\(appCount) app(s) selected"),
                        systemImage: "app.fill"
                    )
                    .foregroundStyle(.primary)
                }

                if categoryCount > 0 {
                    Label(
                        String(localized: "\(categoryCount) category(ies) selected"),
                        systemImage: "folder.fill"
                    )
                    .foregroundStyle(.primary)
                }
            }
            .accessibilityIdentifier("selectionSummary")
        }
    }

    /// Context-sensitive button: "Select Apps to Block" when empty, "Edit Blocked Apps" when populated.
    private func pickerButton(viewModel: AppPickerViewModel) -> some View {
        Button {
            viewModel.presentPicker()
        } label: {
            HStack {
                Image(systemName: viewModel.pickerButtonIcon)
                Text(viewModel.pickerButtonTitle)

                if viewModel.isSaving {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .disabled(viewModel.isSaving)
        .accessibilityIdentifier("selectAppsButton")
    }
}

// MARK: - Preview

/// **Note:** The FamilyActivityPicker does not render in the iOS Simulator.
/// This preview demonstrates the layout with a mock service.
#Preview {
    List {
        Section {
            AppPickerView()
        } header: {
            Text("Blocked Apps")
        }
    }
}
