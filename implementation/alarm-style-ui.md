### Business Requirements: Apple Clock-Style Dashboard Redesign

**1. Relocate "Add Goal" Action to Navigation Bar**
* **Current State Context:** The user currently adds a goal via an inline "Add Goal" button at the bottom of the goals list or an empty state view.
* **Requirement:** The primary method for adding a new goal must be moved to a persistent "+" (plus) icon located in the upper right-hand corner of the Dashboard navigation bar. 
* **Acceptance Criteria:**
    * The "+" button is always visible on the Dashboard, regardless of how many goals exist.
    * Tapping the "+" button opens the unified Add/Edit Goal screen (detailed in Feature 4).
    * The existing inline "Add Goal" button at the bottom of the list should be removed to prevent redundant actions.

**2. Swipe-to-Delete Functionality**
* **Requirement:** Users must be able to remove an existing goal directly from the Dashboard list using a standard iOS swipe gesture.
* **Acceptance Criteria:**
    * Swiping left on any goal row reveals a red "Delete" (trash can) action.
    * Completing the swipe (swiping all the way to the left edge) or tapping the revealed "Delete" button immediately removes the goal from the user's list.
    * Deleting a goal immediately updates the Dashboard UI to reflect the removal.
    * Goal deletions apply immediately. There is no next-day deferral or delayed application for goal removal.

**3. Tap-to-Edit Functionality**
* **Requirement:** The user must be able to easily edit a goal by tapping directly on its card/row in the Dashboard.
* **Acceptance Criteria:**
    * Tapping anywhere on an active or inactive goal row opens the unified Add/Edit Goal screen (detailed in Feature 4).
    * The screen opens pre-populated with the selected goal's existing configuration.
    * Users can edit a goal's configuration values and repeat schedule, but cannot change the goal type of an existing goal.

**4. Unified Add/Edit Screen with "Repeat" Configuration**
* **Requirement:** Consolidate the goal creation and modification flows into a single, unified modal screen with standard iOS top-bar navigation (Cancel/Confirm) and introduce a new "Repeat" scheduling feature.
* **Acceptance Criteria:**
    * **Navigation:** The screen features an "X" (Cancel) button in the upper left to discard changes and close the view, and a "Checkmark" (Confirm/Save) button in the upper right to save changes.
    * **Save Behavior:** New goals apply immediately when confirmed. Edits that make the current day's goal harder may apply immediately. Edits that make the current day's goal easier, or remove today from the repeat schedule, must be saved as a pending change for tomorrow.
    * **Repeat Section:** A new configuration section labeled "Repeat" is added.
    * **Repeat Selection:** Tapping "Repeat" opens a sub-menu listing all seven days of the week. Users can toggle individual days on or off.
    * **Dynamic Summary Text:** Upon confirming the day selection and returning to the Add/Edit screen, the "Repeat" row must display a dynamic summary of the selected days:
        * If Monday through Friday are selected, display **"Weekdays"**.
        * If Saturday and Sunday are selected, display **"Weekends"**.
        * If all 7 days are selected, display **"Every day"**.
        * If a custom combination is selected (e.g., Monday, Wednesday), display the abbreviated comma-separated days (e.g., **"Mon, Wed"**).
        * If no days are selected, the goal is treated as a one-time, today-only goal.
    * **Deferral Confirmation:** When a user attempts to save an edit that must be deferred, the screen presents a confirmation alert before saving.
        * **Title:** "Change Scheduled for Tomorrow"
        * **Message:** "To maintain your current progress and blocker status, this change will take effect tomorrow morning. Do you want to save it?"
        * **Actions:** **[Save for Tomorrow]** | **[Cancel]**

**5. Multi-Day Goal Handling & Dashboard Display States**
* **Requirement:** The Dashboard must intelligently evaluate each goal's "Repeat" schedule against the current day of the week and visually separate applicable goals from non-applicable goals.
* **Acceptance Criteria:**
    * **Active Goals (Scheduled for Today):** Goals that include the current day in their repeat schedule are displayed at the top of the list in their normal, full-color state. They actively track and display current progress.
    * **Inactive Goals (Not Scheduled for Today):** Goals that *do not* include the current day in their repeat schedule are moved to the bottom of the Dashboard list.
    * **Blocking Behavior:** Inactive goals for today do not participate in blocking or unlock evaluation for that day.
    * **Visual Distinction:** Inactive goals must be visually distinct—rendered dimmed, faded, grayed out, or with reduced opacity.
    * **Labeling:** Each goal row on the Dashboard should include a small text indicator showing its active schedule (e.g., "Weekdays", "Weekends", "Tue, Thu") so the user knows at a glance when the goal applies.
    * **Pending Changes:** When an edit is deferred, the existing goal configuration remains in effect for the rest of the current day for progress tracking, blocker evaluation, and active/inactive placement.
    * **Schedule Removal Deferral:** If a user edits the repeat schedule to remove today, the goal still behaves as active for the current day and only transitions to inactive on the next day.
    * **Pending Change Indicator:** Goals with a deferred edit display a visible pending-change indicator on the Dashboard so the user knows an updated configuration will take effect at midnight.

**6. Directional Edit Deferral Policy**
* **Rationale:** Because Make Hay uses health goals to gate phone/app access, the product must prevent edits from becoming an immediate bypass while still allowing users to manage unrealistic or changing goals.
* **Policy:**
    * Edits that make compliance easier defer to the next day.
    * Edits that make compliance harder may apply immediately.
    * Repeat-schedule edits that remove today defer to the next day.
    * This rule preserves blocker integrity without fully preventing same-day editing.