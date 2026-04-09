//
//  PermissionsBannerView.swift
//  Make Hay
//
//  Created by GitHub Copilot on 2/28/26.
//

import SwiftUI

/// Prominent banner displayed on the Dashboard when HealthKit or Screen Time
/// permissions have been revoked or were never granted.
///
/// **Why a dedicated view?** The Dashboard is the primary surface users see.
/// If permissions are silently revoked in the Settings app, the user has no idea
/// why blocking stopped working. This banner makes the broken state immediately
/// obvious and provides a one-tap path to fix it.
struct PermissionsBannerView: View {

    /// Current HealthKit authorization status.
    let healthStatus: HealthAuthorizationStatus

    /// Whether Screen Time (FamilyControls) is currently authorized.
    let screenTimeAuthorized: Bool

    /// Action that routes the user to the permission recovery screen.
    /// **Why a closure?** The banner stays presentation-focused while the parent view
    /// decides where permission recovery lives in the current app architecture.
    let onOpenSettings: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.statusPermissionMissing)

                Text(String(localized: "Permissions Needed"))
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            // Detail text describing which permission(s) are missing.
            Text(detailText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onOpenSettings()
            } label: {
                Text(String(localized: "Open Settings"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.statusPermissionMissing)
            .controlSize(.small)
            .accessibilityIdentifier("permissionsBannerOpenSettings")
        }
        .padding()
        .background(
            Color.statusPermissionMissing.opacity(0.1),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .padding(.horizontal, 16)
        .accessibilityIdentifier("permissionsBanner")
    }

    // MARK: - Helpers

    /// Builds a descriptive string listing which permissions are missing.
    ///
    /// **Why computed?** Keeps the `body` lean and makes the logic easily testable
    /// if extracted to a ViewModel later.
    private var detailText: String {
        let healthMissing = healthStatus == .notDetermined || healthStatus == .denied
        let healthUnconfirmed = healthStatus == .unconfirmed
        let screenTimeMissing = !screenTimeAuthorized

        if healthUnconfirmed && screenTimeMissing {
            return String(localized: "Screen Time still needs approval, and Apple Health access has not been confirmed. Both are required to read your activity and unlock apps.")
        } else if healthMissing && screenTimeMissing {
            return String(localized: "Turn on Apple Health to track your activity and Screen Time to enable app blocking. These let Make Hay unlock your apps when you reach your goals.")
        } else if healthUnconfirmed {
            return String(localized: "Apple Health access was requested, but Make Hay has not confirmed readable data yet. Health data is used to unlock blocked apps.")
        } else if healthMissing {
            return String(localized: "Turn on Apple Health to allow Make Hay to read your activity and unlock your apps when you reach your goals.")
        } else {
            return String(localized: "Turn on Screen Time to block apps until you hit your goals.")
        }
    }

}

// MARK: - Preview

#Preview("Both Missing") {
    PermissionsBannerView(
        healthStatus: .denied,
        screenTimeAuthorized: false,
        onOpenSettings: { }
    )
    .padding()
}

#Preview("Health Missing") {
    PermissionsBannerView(
        healthStatus: .denied,
        screenTimeAuthorized: true,
        onOpenSettings: { }
    )
    .padding()
}

#Preview("Screen Time Missing") {
    PermissionsBannerView(
        healthStatus: .authorized,
        screenTimeAuthorized: false,
        onOpenSettings: { }
    )
    .padding()
}
