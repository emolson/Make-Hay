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

    // MARK: - ViewModel

    /// Owned by this view via `@StateObject` so the edit session survives SwiftUI re-renders.
    @StateObject private var viewModel: AppPickerViewModel

    // MARK: - Initialization

    /// - Parameter blockerService: Injected service for persisting selections and managing shields.
    init(blockerService: any BlockerServiceProtocol) {
        _viewModel = StateObject(
            wrappedValue: AppPickerViewModel(blockerService: blockerService)
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            selectionSummary
            pickerButton
        }
        .familyActivityPicker(
            isPresented: $viewModel.isPickerPresented,
            selection: $viewModel.draftSelection
        )
        .onChange(of: viewModel.isPickerPresented) { _, isPresented in
            // Commit draft only when picker dismisses, not on every binding mutation.
            // If the user tapped Cancel, FamilyActivityPicker leaves draftSelection
            // unchanged, so writing it back to the service is a harmless no-op.
            if !isPresented {
                viewModel.pickerDismissed()
            }
        }
        .task {
            await viewModel.loadCurrentSelection()
        }
        .alert(
            String(localized: "Error"),
            isPresented: $viewModel.showError
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    // MARK: - Subviews

    /// Displays a summary of the committed (persisted) selection.
    @ViewBuilder
    private var selectionSummary: some View {
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
    private var pickerButton: some View {
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
            AppPickerView(blockerService: MockBlockerService())
        } header: {
            Text("Blocked Apps")
        }
    }
}
