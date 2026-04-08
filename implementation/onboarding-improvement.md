### Business Requirements: Retention-Focused Onboarding Redesign

> **Platform Constraint (FamilyControls):** iOS requires Screen Time (FamilyControls) authorization *before* the `FamilyActivityPicker` can be presented. This means blocked-app selection cannot precede the Screen Time permission prompt. The flow below accounts for this constraint.

> **Current State:** Onboarding currently follows Welcome → Health Permission → Screen Time Permission → Completion. The Welcome screen frames the experience around permissions ("Two quick permissions to get started"), the permission screens use functional copy ("Used to read your health goal progress"), and the Completion screen tells the user to go set things up *after* onboarding ("Next, add a goal and choose apps to block"). The user pays all friction costs before experiencing any product value. A recovery path already exists via `PermissionsBannerView` on the Dashboard.

> **Target Flow:**
> 1. **Welcome** — value proposition, no mention of permissions
> 2. **Set Up First Goal** — user picks a goal type, target, and repeat schedule
> 3. **Activation Pitch** — personalized summary referencing the goal; explains permissions are needed to activate
> 4. **Screen Time Permission** — hard gate (required for blocking)
> 5. **Choose Blocked Apps** — `FamilyActivityPicker` (now authorized)
> 6. **Health Permission** — skippable; shown only when the selected goal requires health data
> 7. **Success** — confirms the user's live setup; transitions to Dashboard

> **Design Principle:** Let the user invest effort (goal selection, app selection) before asking for high-friction system permissions. Users who have already configured a personal setup have higher motivation to tap "Allow."

---

**1. Restructure the Onboarding Step Order Around User Investment**
* **Current State Context:** The user currently sees Welcome → Health Permission → Screen Time Permission → Completion. The first interactive action is granting a system permission. Goal creation and blocked-app selection happen entirely post-onboarding on the Dashboard and in Settings respectively.
* **Requirement:** The onboarding flow must let the user configure a goal before any system permission prompt appears. Screen Time authorization must precede blocked-app selection per FamilyControls requirements, but both must follow the goal-setup step.
* **Acceptance Criteria:**
    * The `OnboardingStep` enum is updated to reflect the new step order: `welcome`, `setupGoal`, `activation`, `screenTime`, `chooseApps`, `health` (conditional), `success`.
    * A new user's first interactive action is choosing a goal, not approving a permission.
    * The existing Completion step that says "Next, add a goal and choose apps to block" is removed.
    * Users who have already granted Screen Time or Health in a prior session skip those permission steps automatically.

**2. Add a First Goal Setup Step**
* **Current State Context:** Goal creation currently happens on the Dashboard via the Add Goal sheet after onboarding is complete. Many users never reach this step.
* **Requirement:** Onboarding must include a streamlined goal-setup step where the user selects a goal type and configures its target value.
* **Acceptance Criteria:**
    * The step presents the available goal types (Steps, Active Energy, Exercise, Time Unlock) in a visual card layout consistent with the existing `AddGoalView` pattern.
    * Tapping a goal type reveals a simple target configuration inline or via a pushed sub-step (consistent with `GoalConfigurationView`).
    * The Repeat schedule picker is included in the configuration sub-step, defaulting to "Every day" for new goals (consistent with alarm-style-ui.md Feature 4).
    * Only one goal is required during onboarding. The user can add more goals from the Dashboard later.
    * The configured goal is persisted to `HealthGoal` storage when the user confirms, so it is immediately visible on the Dashboard after onboarding completes.
    * A "Continue" button advances to the next step only after a goal has been configured.

**3. Add a Personalized Activation Pitch Step**
* **Current State Context:** No activation summary exists. The current Completion step uses generic copy that does not reference any user-specific choices.
* **Requirement:** After goal setup, the app must show a concise activation screen that references the user's selected goal and explains that two permissions are needed to make it work.
* **Acceptance Criteria:**
    * The activation screen displays the user's chosen goal type and target in plain language (e.g., "Walk 10,000 steps every day" or "30 minutes of exercise on Weekdays").
    * The screen explains that Screen Time permission is needed to block apps and Health permission is needed to track progress (if applicable).
    * The primary call-to-action button is labeled "Activate" or "Turn It On" — not "Allow" or "Continue."
    * The screen does not reference blocked apps yet, since app selection happens after Screen Time authorization.
    * If both permissions are already granted (e.g., re-onboarding scenario), the activation step auto-advances or shows a brief "Already connected" confirmation.
    * A secondary "I'll set this up later" action is available so users who get cold feet are not trapped in the flow. Tapping it completes onboarding and drops the user onto the Dashboard in a limited state (no goal, no blocked apps). The existing `PermissionsBannerView` and empty-state prompts handle recovery from there.

**4. Screen Time Permission Step (Hard Gate)**
* **Current State Context:** Screen Time permission is currently the second onboarding step. It has no skip option, but the "Open Settings" fallback only appears after an error. The copy reads: "Needed to block apps until you hit your goals."
* **Requirement:** Screen Time remains a hard gate because the `FamilyActivityPicker` and app blocking both require FamilyControls authorization. The copy must be rewritten to focus on user benefit and connect to the goal the user just configured.
* **Acceptance Criteria:**
    * Screen Time cannot be skipped. It is required to proceed to blocked-app selection.
    * The headline reads something benefit-oriented (e.g., "Let's Lock In Your Commitment").
    * The body copy connects Screen Time to the user's goal (e.g., "Screen Time access lets Make Hay block the apps you choose until you hit your goal. You stay in control of which apps are blocked.").
    * If the user denies the system prompt, the step displays a clear recovery message and an "Open Settings" action — not just on error, but also on denial.
    * If Screen Time was already granted, this step is auto-skipped.

**5. Add Blocked-App Selection to Onboarding**
* **Current State Context:** Blocked-app selection currently lives in Settings → Blocked Apps via `AppPickerView`. A new user must discover it independently after onboarding, and many never do.
* **Requirement:** Immediately after Screen Time authorization, onboarding must present the `FamilyActivityPicker` so the user can choose which apps or categories to block.
* **Acceptance Criteria:**
    * The step reuses the existing `AppPickerView` / `AppPickerViewModel` pattern and persists the selection to the same `FamilyActivitySelection` storage used by the rest of the app.
    * The step displays inline text explaining that blocked-app choices can be changed anytime in Settings.
    * If the user dismisses the picker without selecting any apps, the step shows a nudge message (e.g., "No apps selected yet — you can always add them in Settings") and allows the user to continue.
    * The copy leading into the picker provides lightweight guidance to reduce decision paralysis (e.g., "Pick the 2 or 3 apps that distract you the most — like social media or games. You can always change this later.").
    * The step includes a "Select Apps to Block" button that presents the system picker, and a "Continue" button that advances regardless of selection state.
    * The chosen app/category count is displayed after selection so the user sees confirmation of their choice.

**6. Health Permission Step (Conditional, Skippable)**
* **Current State Context:** Health permission is currently the first permission step. The copy reads: "Used to read your health goal progress." A "Skip for Now" button exists.
* **Requirement:** Health permission is shown only when the user's selected goal requires health data (Steps, Active Energy, or Exercise). It is skippable. The copy must be rewritten for benefit and privacy.
* **Acceptance Criteria:**
    * If the user selected a Time Unlock goal (which does not require HealthKit), this step is skipped entirely.
    * If the user selected a health-based goal, the step is shown after blocked-app selection.
    * The headline reads something benefit-oriented (e.g., "Connect Apple Health").
    * The body copy explains the direct benefit and reassures privacy (e.g., "We'll automatically track your progress and unlock your apps the moment you hit your goal. Your health data never leaves your device.").
    * A "Skip for Now" button remains available and advances to the success step.
    * If Health was already granted, this step is auto-skipped.
    * If Health is skipped or denied, the existing `PermissionsBannerView` on the Dashboard surfaces a recovery call-to-action. No additional recovery UI is required beyond what already exists.

**7. Replace the Completion Step With an Outcome-Focused Success State**
* **Current State Context:** The current Completion step displays a generic checkmark and says "Next, add a goal and choose apps to block." This introduces core setup *after* onboarding, undermining the work the user already did in the redesigned flow.
* **Requirement:** The final onboarding step must confirm the user's specific setup and transition them to the Dashboard with no remaining ambiguity about what happens next.
* **Acceptance Criteria:**
    * The success screen displays the user's configured goal (type, target, and schedule summary).
    * If blocked apps were selected, the screen displays the count (e.g., "3 apps will be blocked").
    * If Health was skipped, the screen includes a brief note (e.g., "Connect Apple Health anytime to start automatic tracking.").
    * If all permissions are granted and a goal + apps are configured, the copy confirms activation is complete (e.g., "You're all set. Your apps are blocked until you hit your goal.").
    * The primary button is labeled "Go to Dashboard" and sets `hasCompletedOnboarding = true`.
    * Landing on the success screen triggers a satisfying haptic (`.success`) and a celebratory visual flourish (confetti burst or animated checkmark) to reward the user for completing the high-friction setup.
    * There is no instruction to perform setup that should have already happened.

**8. Add a Step Progress Indicator**
* **Current State Context:** The current onboarding uses `TabView` page dots (4 dots for 4 steps). The redesigned flow has up to 7 steps, making page dots feel long and discouraging.
* **Requirement:** Replace the page-dot indicator with a horizontal progress bar or segmented step indicator that communicates forward momentum without implying a fixed large number of remaining screens.
* **Acceptance Criteria:**
    * A progress indicator is visible at the top of every onboarding step.
    * The indicator reflects the user's current position relative to total steps, accounting for conditional steps (e.g., if Health is skipped, total step count adjusts).
    * The indicator does not display individual step labels or numbers — it communicates proportion, not count.
    * Steps that are auto-skipped (permissions already granted) do not inflate the visible progress.
