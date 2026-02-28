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

    /// SwiftUI environment action for opening URLs.
    /// **Why `@Environment` instead of `UIApplication.shared`?** Keeps the view
    /// purely declarative with no UIKit dependency, and makes the action injectable
    /// in tests and previews.
    @Environment(\.openURL) private var openURL

    /// Current HealthKit authorization status.
    let healthStatus: HealthAuthorizationStatus

    /// Whether Screen Time (FamilyControls) is currently authorized.
    let screenTimeAuthorized: Bool

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.statusPermissionMissing)

                Text(String(localized: "Permissions Missing"))
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            // Detail text describing which permission(s) are missing.
            Text(detailText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Deep-link to the app's Settings page so the user can fix it.
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
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
        let healthMissing = healthStatus != .authorized
        let screenTimeMissing = !screenTimeAuthorized

        if healthMissing && screenTimeMissing {
            return String(localized: "Apple Health and Screen Time access have been revoked. The app cannot track your goals or block apps without both permissions.")
        } else if healthMissing {
            return String(localized: "Apple Health access has been revoked. The app cannot track your health goals without this permission.")
        } else {
            return String(localized: "Screen Time access has been revoked. The app cannot block apps without this permission.")
        }
    }
}

// MARK: - Preview

#Preview("Both Missing") {
    PermissionsBannerView(
        healthStatus: .denied,
        screenTimeAuthorized: false
    )
    .padding()
}

#Preview("Health Missing") {
    PermissionsBannerView(
        healthStatus: .denied,
        screenTimeAuthorized: true
    )
    .padding()
}

#Preview("Screen Time Missing") {
    PermissionsBannerView(
        healthStatus: .authorized,
        screenTimeAuthorized: false
    )
    .padding()
}
