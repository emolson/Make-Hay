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
            
            let appCount = viewModel.persistedSelection.applicationTokens.count
            let categoryCount = viewModel.persistedSelection.categoryTokens.count
            
            // Only show the tip if they haven't selected anything yet
            if appCount == 0 && categoryCount == 0 {
                Text(String(localized: "Start small. Block only your top 3 or 4 biggest distractions."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, -4)
                .padding(12)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
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
            GuardrailInterceptionView(context: .blockedAppsChange) {
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
        
        HStack {
            Image(systemName: appCount == 0 && categoryCount == 0 ? "app.badge" : "checkmark.shield.fill")
                .foregroundStyle(appCount == 0 && categoryCount == 0 ? Color.secondary : Color.green)
                .font(.title2)
            
            Text(summaryText(apps: appCount, categories: categoryCount))
                .font(.subheadline)
                .foregroundStyle(appCount == 0 && categoryCount == 0 ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("selectionSummary")
    }
    
    private func summaryText(apps: Int, categories: Int) -> String {
        if apps == 0 && categories == 0 {
            return String(localized: "No apps selected")
        } else if apps > 0 && categories > 0 {
            return String(localized: "Currently blocking \(apps) apps and \(categories) categories.")
        } else if apps > 0 {
            return String(localized: "Currently blocking \(apps) apps.")
        } else {
            return String(localized: "Currently blocking \(categories) categories.")
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
