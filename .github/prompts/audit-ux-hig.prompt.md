# Objective
Audit the user interface for strict compliance with Apple's Human Interface Guidelines (HIG), specifically regarding HealthKit and FamilyControls.

# Instructions
1. **System Pickers:** Review `AppPickerView.swift`. Ensure we are using the native `FamilyActivityPicker` provided by Apple. Do not attempt to build a custom UI for selecting restricted apps, as this violates Screen Time privacy rules.
2. **HealthKit Terminology:** Audit all user-facing strings in `OnboardingView.swift` and `GoalConfigurationView.swift`. Ensure we use Apple's approved terminology (e.g., "Apple Health" instead of just "Health App" or "HealthKit").
3. **Design System & Visual Feedback:** Verify no hardcoded colors (raw SwiftUI colors or hex values) are present in the Views. All colors and styles must reference semantic names from `Make Hay/DesignSystem/DesignSystem.swift` and `Make Hay/Assets.xcassets`. Review assets (`StatusBlocked.colorset`, `GoalRingTrack.colorset`) to ensure contrast ratios meet accessibility standards.

# Output
Provide a list of UX/UI violations according to Apple's HIG and suggest SwiftUI modifier changes to natively adopt Apple's styling.