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
/// **Why a separate view?** This encapsulates the FamilyActivityPicker logic and state,
/// keeping SettingsView focused on layout. It also allows for easier testing and reuse.
///
/// **Note:** The `.familyActivityPicker` modifier does NOT render in the iOS Simulator.
/// You must test this feature on a physical device with Family Controls capability enabled.
struct AppPickerView: View {
    
    // MARK: - Properties
    
    /// The blocker service for persisting the app selection.
    let blockerService: any BlockerServiceProtocol
    
    // MARK: - State
    
    /// Controls the presentation of the family activity picker sheet.
    @State private var isPickerPresented: Bool = false
    
    /// The current app and category selection for blocking.
    @State private var selection: FamilyActivitySelection = FamilyActivitySelection()
    
    /// Indicates if an error occurred while saving the selection.
    @State private var showError: Bool = false
    
    /// The error message to display.
    @State private var errorMessage: String = ""
    
    /// Indicates if the selection is being saved.
    @State private var isSaving: Bool = false
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            selectionSummary
            
            HStack(spacing: 12) {
                selectAppsButton
                
                if hasSelection {
                    clearSelectionButton
                }
            }
        }
        .familyActivityPicker(
            isPresented: $isPickerPresented,
            selection: $selection
        )
        .onChange(of: selection) { _, newSelection in
            Task {
                await saveSelection(newSelection)
            }
        }
        .task {
            await loadCurrentSelection()
        }
        .alert(
            String(localized: "Error"),
            isPresented: $showError
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Computed Properties
    
    /// Whether the user has selected any apps or categories.
    private var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
    }
    
    // MARK: - Subviews
    
    /// Displays a summary of the current selection.
    @ViewBuilder
    private var selectionSummary: some View {
        let appCount = selection.applicationTokens.count
        let categoryCount = selection.categoryTokens.count
        
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
    
    /// Button to present the family activity picker.
    private var selectAppsButton: some View {
        Button {
            isPickerPresented = true
        } label: {
            HStack {
                Image(systemName: "plus.app")
                Text(String(localized: "Select Apps to Block"))
                
                if isSaving {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .disabled(isSaving)
        .accessibilityIdentifier("selectAppsButton")
    }
    
    /// Button to clear the current selection.
    private var clearSelectionButton: some View {
        Button(role: .destructive) {
            clearSelection()
        } label: {
            HStack {
                Image(systemName: "xmark.circle.fill")
                Text(String(localized: "Clear"))
            }
        }
        .disabled(isSaving)
        .accessibilityIdentifier("clearSelectionButton")
    }
    
    // MARK: - Private Methods
    
    /// Loads the current selection from the blocker service.
    private func loadCurrentSelection() async {
        selection = await blockerService.getSelection()
    }
    
    /// Saves the selection to the blocker service and applies shields immediately.
    /// - Parameter newSelection: The updated `FamilyActivitySelection` to persist.
    private func saveSelection(_ newSelection: FamilyActivitySelection) async {
        isSaving = true
        defer { isSaving = false }
        
        do {
            try await blockerService.setSelection(newSelection)
            
            // Apply or remove shields immediately based on whether apps are selected.
            // **Why apply shields here?** The user expects changes to take effect right away.
            // If we only persist the selection without updating shields, the blocking
            // state won't change until some other code path calls updateShields.
            let hasAppsSelected = !newSelection.applicationTokens.isEmpty || !newSelection.categoryTokens.isEmpty
            try await blockerService.updateShields(shouldBlock: hasAppsSelected)
            
            // Provide haptic feedback on successful save
            await MainActor.run {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        } catch {
            // Provide haptic feedback on error
            await MainActor.run {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    /// Clears the current app and category selection.
    private func clearSelection() {
        // Setting to empty selection will trigger the onChange handler
        selection = FamilyActivitySelection()
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
