# Objective
Harden the Swift Concurrency model and evaluate the reliability of background execution tasks.

# Context
Make Hay uses `BackgroundHealthMonitor` to track fitness goals while the app is not active. Background execution on iOS is highly restricted by the OS.

# Instructions
1. **Swift Concurrency Rules:** Scan the codebase for proper use of `async/await`, `Task`, and `actor`. Identify code using legacy `DispatchQueue` or Combine completion blocks. Ensure `@MainActor` is applied to ViewModels, and verify that types crossing actor boundaries are strict `Sendable`.
2. **Background Reliability:** Review `BackgroundHealthMonitor.swift` and `DeviceActivityMonitor.swift`. Are background tasks being properly registered and completed using the `BGTaskScheduler`? 
3. **Stale Data Handling:** Evaluate what happens if HealthKit background delivery is delayed by the OS. Propose a fallback mechanism (e.g., forcing a sync on `scenePhase` becoming active) to ensure the user is not unfairly locked out of their apps due to OS throttling.

# Output
Propose architectural changes to ensure background monitoring is as reliable as Apple's sandbox permits. Highlight any concurrency warnings that would appear in Swift 6's strict concurrency mode.