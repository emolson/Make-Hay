# Objective
Audit the codebase against Apple's App Store Review Guidelines, specifically focusing on HealthKit (Guideline 5.1.3) and Safety (Guideline 1.4).

# Instructions
1. **HealthKit Justification:** Review `Info.plist` and `PermissionsBannerView.swift`. Ensure the descriptions for `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription` explicitly state *how* the data is used to unlock apps, rather than just asking for general permission.
2. **Data Sharing Prevention:** Scan `HealthService.swift`. Ensure there are no third-party analytics SDKs or network calls transmitting HealthKit data off-device. 
3. **FamilyControls Transparency:** Review `OnboardingViewModel.swift`. Ensure the app clearly explains that it uses Screen Time APIs to restrict access, and that it provides an easy way to revoke this access.

# Output
Provide a checklist of App Store compliance risks and generate the exact string values needed for `Info.plist` to satisfy App Review.