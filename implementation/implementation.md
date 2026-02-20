# Implementation Plan: Health-Gated Productivity App

## 1. Architecture & Patterns

### Core Architectural Standards
- **Pattern:** MVVM with lightweight navigation (TabView + NavigationStack)
- **Concurrency:** Strict Swift 6 concurrency (Actors for services, @MainActor for UI/ViewModels)
- **UI:** Pure SwiftUI with `NavigationStack`
- **Minimum iOS Version:** iOS 16.0+ (required for `FamilyActivitySelection` Codable conformance)
- **Accessibility:** All interactive elements must have `.accessibilityIdentifier()` for UI testing
- **Localization:** All user-facing strings must use `String(localized:)`

### Project Structure
```text
Make Hay/
├── App/
│   ├── Make_HayApp.swift       # Entry point
│   └── AppDependencyContainer.swift # DI Container
├── Features/
│   ├── Onboarding/             # Permissions (Health + Screen Time)
│   ├── Dashboard/              # Main view showing progress
│   └── Settings/               # Goal selection & App blocking picker
├── Services/
│   ├── HealthService.swift     # HealthKit integration (Actor)
│   └── BlockerService.swift    # FamilyControls & ManagedSettings (Actor)
├── Models/
│   ├── HealthGoal.swift        # Struct for goals (Steps, Energy, etc.)
│   └── AppSelection.swift      # Wrapper for FamilyActivitySelection
├── Mocks/
│   ├── MockHealthService.swift  # For previews and unit tests
│   └── MockBlockerService.swift  # For previews and unit tests
└── Resources/
    └── Info.plist              # Privacy descriptions
```

---

## 2. Prompt-Driven Backlog

### Slice 0: Project Scaffolding

#### Story 0: Project Setup & App Entry Point
**Goal:** Establish folder structure, protocols, DI container, and app navigation.
**LLM Prompt:**
```text
Act as a Senior iOS Architect. Set up the foundational project structure for "Make Hay".

1. **Folder Structure**: Create the following empty folders:
   - `Make Hay/App/`
   - `Make Hay/Features/Onboarding/`
   - `Make Hay/Features/Dashboard/`
   - `Make Hay/Features/Settings/`
   - `Make Hay/Services/`
   - `Make Hay/Services/Protocols/`
   - `Make Hay/Models/`
   - `Make Hay/Mocks/`

2. **Protocols**: Create `Services/Protocols/HealthServiceProtocol.swift`:
   ```swift
   protocol HealthServiceProtocol: Actor {
       func requestAuthorization() async throws
       func fetchDailySteps() async throws -> Int
   }
   ```
   Create `Services/Protocols/BlockerServiceProtocol.swift`:
   ```swift
   protocol BlockerServiceProtocol: Actor {
       func requestAuthorization() async throws
       func updateShields(shouldBlock: Bool) async throws
   }
   ```

3. **DI Container**: Create `App/AppDependencyContainer.swift`:
   - A class that instantiates and holds references to all services.
   - Inject protocols, not concrete types.

4. **App Entry**: Update `Make_HayApp.swift`:
   - Create the `AppDependencyContainer`.
   - Use a `@State` variable `hasCompletedOnboarding` (persisted via `@AppStorage`).
   - If not onboarded, show `OnboardingView`. Otherwise, show main `TabView`.

5. **Navigation**: Create a simple `TabView` in `App/MainTabView.swift` with two tabs:
   - "Dashboard" (DashboardView)
   - "Settings" (SettingsView)
   - Add `.accessibilityIdentifier()` to each tab.

6. **Mocks**: Create mock implementations for previews and testing:
   - Create `Mocks/MockHealthService.swift`:
     ```swift
     actor MockHealthService: HealthServiceProtocol {
         var mockSteps: Int = 5_000
         var shouldThrowError: Bool = false
         
         func requestAuthorization() async throws {
             if shouldThrowError { throw HealthServiceError.authorizationDenied }
         }
         
         func fetchDailySteps() async throws -> Int {
             if shouldThrowError { throw HealthServiceError.queryFailed(underlying: NSError(domain: "", code: 0)) }
             return mockSteps
         }
     }
     ```
   - Create `Mocks/MockBlockerService.swift`:
     ```swift
     actor MockBlockerService: BlockerServiceProtocol {
         var isBlocking: Bool = false
         var shouldThrowError: Bool = false
         
         func requestAuthorization() async throws {
             if shouldThrowError { throw BlockerServiceError.authorizationFailed }
         }
         
         func updateShields(shouldBlock: Bool) async throws {
             if shouldThrowError { throw BlockerServiceError.notAuthorized }
             isBlocking = shouldBlock
         }
     }
     ```
```

### Slice 1: Health Foundation (The Key)

#### Story 1: Health Permissions & Basic Read
**Goal:** HealthKit integration for reading steps with proper error handling.
**LLM Prompt:**
```text
Act as a Senior iOS Architect. Implement the HealthKit foundation for "Make Hay".

1. **Configuration**: Provide the `NSHealthShareUsageDescription` key text for `Info.plist`. (I will manually add the HealthKit capability in Xcode.)

2. **Error Enum**: Create `Services/HealthServiceError.swift`:
   ```swift
   enum HealthServiceError: Error, Sendable {
       case healthKitNotAvailable
       case authorizationDenied
       case queryFailed(underlying: Error)
   }
   ```

3. **Service**: Create `Services/HealthService.swift` as an `actor` conforming to `HealthServiceProtocol`.
   - Implement `requestAuthorization()` that throws `HealthServiceError`.
   - Implement `fetchDailySteps()` using `HKStatisticsQuery` for today's step count.
   - Use strict concurrency (Sendable types).

4. **ViewModel**: Create `Features/Dashboard/DashboardViewModel.swift` (@MainActor, ObservableObject).
   - Inject `any HealthServiceProtocol` via init.
   - Expose `currentSteps: Int`, `isLoading: Bool`, `errorMessage: String?`.
   - Implement `func loadSteps() async`.

5. **View**: Create `Features/Dashboard/DashboardView.swift`.
   - Display the step count prominently.
   - Show loading indicator when fetching.
   - Show error state with retry button if authorization fails.
   - Use `String(localized:)` for all user-facing text.
   - Add `.accessibilityIdentifier()` to key elements: step count label, retry button.
   - Include a `#Preview` using `MockHealthService`.
```

#### Story 2: Set Daily Goal
**Goal:** Allow user to configure their target with persistence.
**LLM Prompt:**
```text
Implement the Daily Goal persistence and UI for "Make Hay".

1. **Model**: Create `Models/HealthGoal.swift`:
   ```swift
   struct HealthGoal: Codable, Sendable, Equatable {
       var dailyStepTarget: Int = 10_000
   }
   ```

2. **Settings View**: Create `Features/Settings/SettingsView.swift`.
   - Use `@AppStorage("dailyStepGoal")` to persist the goal (default 10,000).
   - Provide a `Stepper` to adjust the value in increments of 500.
   - Display the current goal value.
   - Use `String(localized:)` for all labels.
   - Add `.accessibilityIdentifier("stepGoalStepper")` to the stepper.
   - Include a `#Preview`.

3. **Dashboard Update**: Update `DashboardViewModel`:
   - Add a `@Published var dailyStepGoal: Int` (read from AppStorage or injected).
   - Calculate `var progress: Double { Double(currentSteps) / Double(dailyStepGoal) }`.
   - Expose `var isGoalMet: Bool { currentSteps >= dailyStepGoal }`.

4. **UI Update**: Update `DashboardView`:
   - Add a circular progress ring showing progress toward the goal.
   - Display "X / Y steps" text using `String(localized:)` with interpolation.
   - Show a celebratory state (e.g., checkmark, color change) when `isGoalMet` is true.
   - Add `.accessibilityIdentifier("progressRing")` and `.accessibilityIdentifier("goalMetBadge")`.
```

### Slice 2: Onboarding & Permissions

#### Story 3: Onboarding Flow
**Goal:** Guide user through Health + Screen Time permissions before accessing the app.
**LLM Prompt:**
```text
Implement the Onboarding flow for "Make Hay".

1. **View**: Create `Features/Onboarding/OnboardingView.swift`.
   - A multi-step onboarding using a `TabView` with `PageTabViewStyle` or a custom stepper.
   - **Step 1 (Welcome)**: Explain the app concept. "Earn your screen time by hitting your health goals."
   - **Step 2 (Health)**: Request HealthKit permission. Show a "Connect Apple Health" button that calls `healthService.requestAuthorization()`. Handle success/error states.
   - **Step 3 (Screen Time)**: Request FamilyControls permission. Show a "Enable Screen Time" button. Handle success/error states.
   - **Step 4 (Done)**: Confirmation. Button to "Get Started" that sets `hasCompletedOnboarding = true`.
   - Use `String(localized:)` for all text.
   - Add `.accessibilityIdentifier()` to each button: `"connectHealthButton"`, `"enableScreenTimeButton"`, `"getStartedButton"`.

2. **ViewModel**: Create `Features/Onboarding/OnboardingViewModel.swift` (@MainActor).
   - Inject `HealthServiceProtocol` and `BlockerServiceProtocol`.
   - Track `currentStep: Int`.
   - Track `healthPermissionGranted: Bool` and `screenTimePermissionGranted: Bool`.
   - Implement `func requestHealthPermission() async` and `func requestScreenTimePermission() async`.

3. **Navigation**: Ensure `Make_HayApp.swift` shows `OnboardingView` when `hasCompletedOnboarding == false`.

4. **Include `#Preview`** with mocked services.
```

### Slice 3: Blocking Foundation (The Lock)

#### Story 4: Screen Time Authorization & App Selection
**Goal:** Setup FamilyControls and the app picker with proper error handling.
**LLM Prompt:**
```text
Implement the Screen Time blocking foundation for "Make Hay".

1. **Configuration**: (I will manually add `FamilyControls` capability in Xcode.)

2. **Error Enum**: Create `Services/BlockerServiceError.swift`:
   ```swift
   enum BlockerServiceError: Error, Sendable {
       case authorizationFailed
       case shieldUpdateFailed(underlying: Error)
       case notAuthorized
   }
   ```

3. **Service**: Create `Services/BlockerService.swift` as an `actor` conforming to `BlockerServiceProtocol`.
   - Import `FamilyControls` and `ManagedSettings`.
   - Implement `requestAuthorization()` using `AuthorizationCenter.shared.requestAuthorization(for: .individual)`.
   - Store `FamilyActivitySelection` as a property.
   - Implement `func setSelection(_ selection: FamilyActivitySelection)`.
   - Persist the selection to a file in the app's documents directory (encode using PropertyListEncoder since `FamilyActivitySelection` conforms to Codable as of iOS 16+).

4. **Picker UI**: Create `Features/Settings/AppPickerView.swift`.
   - Use the `.familyActivityPicker(isPresented:selection:)` modifier.
   - Bind the selection to a `@State` variable.
   - On dismiss, call `blockerService.setSelection()`.
   - Use `String(localized:)` for button labels.
   - Add `.accessibilityIdentifier("selectAppsButton")`.
   - Include a `#Preview` using `MockBlockerService` (note: picker won't render in simulator).
```

#### Story 5: Manual Toggle (Internal Test)
**Goal:** Verify shielding works without health data. (Device-only testing.)
**LLM Prompt:**
```text
Implement the Shielding logic for "Make Hay".

1. **Configuration**: (I will manually add `ManagedSettings` capability.)

2. **Service Update**: Extend `BlockerService`:
   - Import `ManagedSettings`.
   - Create a private `ManagedSettingsStore` instance.
   - Implement `updateShields(shouldBlock: Bool) async throws`:
     - If `shouldBlock == true`: Apply the saved `FamilyActivitySelection` to `store.shield.applications` and `store.shield.applicationCategories`.
     - If `shouldBlock == false`: Set `store.shield.applications = nil` and `store.shield.applicationCategories = nil`.

3. **Debug UI**: Add a "Debug" section to `SettingsView`:
   - Add a Toggle "Force Block Apps" bound to a `@State var isForceBlocking: Bool`.
   - On toggle change, call `await blockerService.updateShields(shouldBlock: isForceBlocking)`.
   - Add a note: "⚠️ This only works on a physical device."
   - Use `String(localized:)` for labels.
   - Add `.accessibilityIdentifier("forceBlockToggle")`.

4. **Testing Note**: FamilyControls/ManagedSettings do NOT work in Simulator. Test on a real device.
```

### Slice 4: The Gate (Integration)

#### Story 6: The Health Gate Logic
**Goal:** Connect Health status to the Blocker with lifecycle management.
**LLM Prompt:**
```text
Connect the Health data to the Blocker service in "Make Hay".

1. **Integration**: Update `DashboardViewModel`:
   - Inject `BlockerServiceProtocol` in addition to `HealthServiceProtocol`.
   - Add a private function `checkGoalStatus() async`.

2. **Logic** in `checkGoalStatus()`:
   ```swift
   if currentSteps < dailyStepGoal {
       try? await blockerService.updateShields(shouldBlock: true)
   } else {
       try? await blockerService.updateShields(shouldBlock: false)
   }
   ```

3. **Call Site**: Call `checkGoalStatus()` after every `loadSteps()` completes.

4. **Lifecycle**: In `DashboardView`, observe `scenePhase`:
   ```swift
   @Environment(\.scenePhase) var scenePhase
   .onChange(of: scenePhase) { _, newPhase in
       if newPhase == .active {
           Task { await viewModel.loadSteps() }
       }
   }
   ```
   This ensures the gate is checked every time the app is foregrounded.
```

#### Story 7: Daily Reset
**Goal:** Ensure lock re-engages at midnight.
**LLM Prompt:**
```text
Implement the Daily Reset logic for "Make Hay".

1. **Persistence**: Store `lastCheckedDate` in `@AppStorage("lastCheckedDate")` as a String (ISO8601 formatted).

2. **Logic**: In `DashboardViewModel`, create `func checkForNewDay()`:
   - Compare `lastCheckedDate` to today's date.
   - If different:
     - Update `lastCheckedDate` to today.
     - Force a refresh of steps (which will be low/zero at midnight).
     - Call `checkGoalStatus()` which will re-engage the block.

3. **Call Site**: Call `checkForNewDay()` at the start of `loadSteps()`.

4. **Behavior**: At 00:01, if user opens app:
   - `checkForNewDay()` detects new day.
   - `loadSteps()` returns today's steps (likely 0).
   - `checkGoalStatus()` sees `0 < 10000`, calls `updateShields(shouldBlock: true)`.
   - Apps are blocked again.
```

---

### Slice 5: Background Health Delivery

#### Story 8: HKObserverQuery & Background Delivery
**Goal:** Close the HealthKit-to-Screen Time sync gap. When a user hits their step goal while the app is in the background, shields should lift automatically without requiring the user to open the app.

**Problem:** The app only evaluates goals during `.scenePhase == .active`. If Apple Health records steps while Make Hay is backgrounded, shields remain up until the user manually opens the app.

**Solution:** Register `HKObserverQuery` instances and call `enableBackgroundDelivery(for:frequency:)` for all tracked health types. When HealthKit writes new data, it wakes the app briefly, allowing goal evaluation and shield updates.

**Architecture:**
- **`BackgroundHealthMonitorProtocol`** (`Services/Protocols/`): Actor protocol with `startMonitoring()` and `stopMonitoring()` methods.
- **`BackgroundHealthMonitor`** (`Services/`): Actor that owns the observer queries and coordinates evaluation:
  1. On `startMonitoring()`, registers `HKObserverQuery` + `enableBackgroundDelivery` for `stepCount`, `activeEnergyBurned`, `appleExerciseTime`.
  2. When an observer query fires, loads `HealthGoal` from `SharedStorage`, fetches fresh data via `HealthServiceProtocol`, evaluates via `GoalBlockingEvaluator.shouldBlock()`, and updates shields via `BlockerServiceProtocol.updateShields()`.
  3. Fail-safe: if health data fetch fails, shields remain unchanged.
- **`MockBackgroundHealthMonitor`** (`Mocks/`): Test double tracking call counts.
- **Shared `HKHealthStore`**: `AppDependencyContainer` creates one store, injected into both `HealthService` and `BackgroundHealthMonitor`.

**Entitlement:** Added `com.apple.developer.healthkit.background-delivery` to app entitlements.

**Lifecycle:** `startMonitoring()` is called during `AppDependencyContainer.init()` because observer queries and `enableBackgroundDelivery` registrations do not persist across app terminations.

**Frequency:** `.hourly` — Apple's most frequent background delivery cadence. When the app is in memory, observer queries fire more frequently (on each HealthKit write).
```
