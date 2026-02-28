//
//  EmergencyUnlockView.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/3/26.
//

import SwiftUI

/// Modal view requiring cognitive friction to confirm an emergency goal change.
/// Forces the user to type a random code, engaging System 2 thinking to prevent impulsive bypassing.
///
/// **Why this works:** Reading and typing a number interrupts the automatic "tap-tap-tap"
/// impulse loop, making the user consciously acknowledge they're breaking their commitment.
struct EmergencyUnlockView: View {
    
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State
    
    /// The random 4-digit verification code displayed to the user.
    private let verificationCode: String
    
    /// The code entered by the user.
    @State private var enteredCode: String = ""
    
    /// Whether the entered code matches the verification code.
    @State private var isCodeValid: Bool = false

    /// Focus state for the verification text field.
    @FocusState private var isCodeFieldFocused: Bool
    
    /// Callback invoked when the user successfully confirms the emergency unlock.
    let onConfirm: () -> Void

    /// Context-specific warning text shown above the verification challenge.
    let warningDescription: String
    
    // MARK: - Initialization
    
    init(
        warningDescription: String = String(localized: "Emergency unlocks forfeit today's progress. This change will take effect immediately."),
        onConfirm: @escaping () -> Void
    ) {
        self.warningDescription = warningDescription
        self.onConfirm = onConfirm
        // Generate a random 4-digit code
        self.verificationCode = String(format: "%04d", Int.random(in: 0...9999))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        warningIcon
                            .padding(.top, 24)
                        
                        warningText
                        
                        verificationSection
                            .id("codeEntry")
                        
                        // Extra space so scroll-to can lift the field above the keyboard
                        Spacer()
                            .frame(height: 120)
                    }
                    .padding(.horizontal)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: isCodeFieldFocused) { _, focused in
                    guard focused else { return }
                    withAnimation {
                        proxy.scrollTo("codeEntry", anchor: .center)
                    }
                }
            }
            .navigationTitle(String(localized: "Emergency Unlock"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                    .accessibilityIdentifier("cancelEmergencyButton")
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(String(localized: "Done")) {
                        isCodeFieldFocused = false
                    }
                    .accessibilityIdentifier("dismissKeyboardButton")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            confirmButton
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)
        }
        .onChange(of: enteredCode) { _, newValue in
            isCodeValid = newValue == verificationCode
        }
    }
    
    // MARK: - View Components
    
    private var warningIcon: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 60))
            .foregroundStyle(Color.statusWarning)
            .accessibilityIdentifier("emergencyWarningIcon")
    }
    
    private var warningText: some View {
        VStack(spacing: 12) {
            Text(String(localized: "Emergency Unlock"))
                .font(.title2)
                .fontWeight(.bold)
            
            Text(warningDescription)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityIdentifier("emergencyWarningText")
    }
    
    private var verificationSection: some View {
        VStack(spacing: 16) {
            Text(String(localized: "Type this code to confirm:"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text(verificationCode)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .tracking(8)
                .foregroundStyle(.primary)
                .accessibilityIdentifier("verificationCode")
            
            TextField(String(localized: "Enter code"), text: $enteredCode)
                .font(.system(size: 32, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .submitLabel(.done)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .focused($isCodeFieldFocused)
                .accessibilityIdentifier("codeEntryField")
                .onChange(of: enteredCode) { _, newValue in
                    // Limit to 4 digits
                    if newValue.count > 4 {
                        enteredCode = String(newValue.prefix(4))
                    }
                }
        }
    }
    
    private var confirmButton: some View {
        Button {
            isCodeFieldFocused = false
            onConfirm()
            dismiss()
        } label: {
            Text(String(localized: "Confirm Emergency Unlock"))
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.statusWarning)
        .controlSize(.large)
        .disabled(!isCodeValid)
        .accessibilityIdentifier("confirmEmergencyButton")
    }
}

// MARK: - Preview

#Preview {
    EmergencyUnlockView {
        print("Emergency unlock confirmed")
    }
}
