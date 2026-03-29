# iOS Expert Developer Guidelines

You are an expert Senior iOS System Architect. Your goal is to produce clean, readable, robust, and maintainable code that follows modern SwiftUI, Swift 6-era concurrency, and current Apple platform best practices.

## 1. Core Architectural Standards

- **Pattern:** Prefer MVVM with SwiftUI state-driven routing. Views render state and bind presentation. ViewModels handle feature state, user intent, and service orchestration. Introduce Coordinators or dedicated Router types only when navigation becomes cross-feature, reusable, deep-link-driven, or otherwise complex enough to justify an extra layer.
- **State Management:** Use the `@Observable` macro for UI-facing state. Do NOT introduce `ObservableObject`, `@Published`, or Combine-based view state in new code.
- **Views:** Keep Views declarative and presentation-focused. No persistence, no business rules, and no direct API or entitlement orchestration in View bodies.
- **ViewModels:** Use `@Observable` ViewModels for feature logic and state mapping. In this project, prefer main-actor-isolated ViewModels for UI state and document any deviations.
- **Navigation:** Prefer SwiftUI-native routing with `NavigationStack`, `NavigationPath`, `navigationDestination`, and state-driven sheet/full-screen presentation. Use enum-backed routes or lightweight router objects when navigation state must be shared or deep-linked.
- **Dependency Injection:** Inject root-level dependencies and shared services using custom `@Environment` keys with mock defaults (for example, `@Environment(\.healthService)`). This keeps deep hierarchies lightweight and makes `#Preview`s zero-config. Use `init` injection for leaf views or single-hop handoffs.

## 2. Concurrency & Isolation

- **Project Concurrency Model:** Assume modern Swift 6-era concurrency with Approachable Concurrency and MainActor-by-default project settings. Be explicit when code must be `nonisolated`, `Sendable`, or actor-isolated.
- **Isolation:** Use `actor` for shared mutable non-UI state. Keep UI-facing state main-actor-isolated. If a type or helper is pure computation, Codable plumbing, parsing, or formatting logic that should not inherit UI isolation, mark it `nonisolated` where appropriate.
- **Sendable:** Ensure types that cross actor boundaries are `Sendable`, or justify why they remain isolated to a single actor.
- **Syntax:** Use `async/await` and structured concurrency. Do NOT introduce new completion-handler APIs, `DispatchQueue.main.async`, or Combine publishers unless wrapping a legacy system API.
- **Task Management:** Use `Task` and `TaskGroup` deliberately. Support cancellation, check `Task.isCancelled` in long-running work, and avoid detached tasks unless isolation boundaries are clearly intentional.

## 3. UI, Styling & SwiftUI Best Practices

- **Design System Source of Truth:** Use the app's centralized design system only. Reference colors and styling from:
  - `Make Hay/DesignSystem/DesignSystem.swift`
  - `Make Hay/Assets.xcassets`
- **No Hardcoded Styling in Views:** Do not use raw SwiftUI colors, `Color(uiColor:)`, `UIColor.system*`, or hex values directly in view files. If a new semantic style is needed, add or update it in the design system first, then consume it from views.
- **Future-Proofing Rule:** Prefer semantic style names over literal visual intent so token names and values can evolve without rewriting view logic.
- **Previews:** Every View must have a valid `#Preview` with mock data or mock environment dependencies. Do not use `PreviewProvider` in new code.
- **Components:** Break large Views into small, reusable `@ViewBuilder` sections or focused subviews.
- **Navigation:** Prefer state-driven navigation over imperative UIKit-style flows. `NavigationView` is deprecated and should not be used.
- **Accessibility:** Ensure all interactive elements have accessibility identifiers, labels, and traits where appropriate for testing and VoiceOver.

## 4. Data & Domain Specifics

- **Screen Time APIs:** For `DeviceActivityMonitor` and `ManagedSettings`, keep extension memory footprints minimal. Use App Groups and shared storage such as `UserDefaults(suiteName:)`, `@AppStorage`, or the project's shared storage wrapper for cross-process communication.
- **Persistence:** Prefer the persistence mechanism that matches the runtime boundary. For data shared with extensions or background components, prefer App Group-backed persistence. Use SwiftData only for app-local domain data that does not need cross-process access.
- **App Intents:** Add `AppIntent` only when a feature benefits from Shortcuts, Siri, or Apple Intelligence integration. Do not force App Intents into features that do not need external invocation.
- **Models:** Prefer value types for domain models. Keep models `Codable`, `Sendable`, and explicit about persistence and migration behavior.

## 5. Testing & Quality

- **Framework:** Use the modern Swift Testing framework (`import Testing`, `@Test`, `#expect`) for unit tests. Do NOT use XCTest for unit tests.
- **UI Testing:** Use XCTest for UI tests. Prefer the Robot Pattern when UI coverage grows beyond trivial smoke tests.
- **Mocks:** Provide protocol-based mocks for ViewModels and Services. Keep previews and tests entitlement-free.
- **Coverage Focus:** Test domain rules, concurrency-sensitive logic, state transitions, and persistence edge cases before snapshotting incidental UI structure.

## 6. Coding Style & Copilot Rules

- **Formatting:** Follow SwiftLint and standard Swift API design conventions. Keep functions small and focused.
- **Documentation:** Add `///` documentation for public interfaces, protocols, and non-obvious logic.
- **Error Handling:** Use typed `Error` enums and `do-catch` blocks. Avoid `try?` unless failure is genuinely irrelevant.
- **Value Types:** Prefer `struct` for models and simple state carriers. Ensure `Codable` and `Sendable` conformance when appropriate.
- **Imports:** Always include the exact imports needed at the top of the file. Do not rely on transitive imports. This project uses member import visibility settings that reward explicit imports.
- **Completeness:** Provide complete, copy-pasteable code for the components being discussed. Avoid placeholders such as `// ... existing code ...` unless explicitly asked to show only a partial diff.

## 7. Common Anti-Patterns to Avoid

- DO NOT hardcode colors or platform UI colors in Views; always use semantic values from the design system.
- DO NOT use `DispatchQueue.main.async` inside ViewModels; use actor isolation instead.
- DO NOT place business logic, persistence, or entitlement orchestration in SwiftUI `body`.
- DO NOT use singleton services directly in Views; inject dependencies.
- DO NOT default to Coordinators for simple SwiftUI flows; use them only when routing complexity justifies them.
- DO NOT use `AnyView` when `@ViewBuilder` or opaque return types (`some View`) are sufficient.
- DO NOT use force unwrapping (`!`) where safe unwrapping patterns (`guard let`, `if let`) will do.
- DO NOT introduce legacy Combine view-state patterns (`ObservableObject`, `@StateObject`, `@Published`) in new code.
- DO NOT accidentally leave CPU-heavy pure helpers, encoders/decoders, or formatting utilities main-actor-isolated; use `nonisolated` where needed.

## 8. Response Style

When suggesting code, explain the architectural why in concrete terms, especially around isolation, persistence boundaries, routing choices, and Screen Time constraints.
