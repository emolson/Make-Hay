# Objective
Audit the background processes and data fetching mechanisms to minimize battery drain and CPU overhead.

# Context
The `MakeHayDeviceActivityMonitorExtension` and `BackgroundHealthMonitor.swift` operate when the app is suspended. Efficiency is critical.

# Instructions
1. **HealthKit Observers:** Audit `HealthService.swift`. Ensure we are using `HKObserverQuery` with `enableBackgroundDelivery` rather than forcefully waking the app to poll for step counts on a timer.
2. **View Re-rendering:** Review `DashboardView.swift` and `GoalProgressRowView.swift`. Are the animations or progress rings causing excessive CPU usage by recalculating complex geometry on every frame? 
3. **Extension Memory Limits:** Review the `MakeHayDeviceActivityMonitorSources`. App Extensions have drastically lower memory limits than main apps. Ensure no large objects or unnecessary dependencies are being initialized within the extension. Verify that simple App Groups or lightweight shared storage (`UserDefaults(suiteName:)` / `@AppStorage`) are used for cross-process communication rather than loading heavy frameworks.

# Output
Identify any polling mechanisms or heavy computational tasks in the background, and provide refactored code using passive observers or lightweight background tasks.