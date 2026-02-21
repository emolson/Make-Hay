//
//  MakeHayDeviceActivityMonitor.swift
//  MakeHayDeviceActivityMonitorExtension
//
//  Created by GitHub Copilot on 2/19/26.
//

import DeviceActivity
import ManagedSettings

/// Device Activity monitor that performs background-resilient time unlock actions.
///
/// **Why check both legacy and per-weekday names?** During the transition to weekly
/// schedules, earlier schedules using `.makeHayTimeUnlock` may still be registered.
/// Matching all known names ensures shields are cleared regardless of which generation
/// of schedule is active.
final class MakeHayDeviceActivityMonitor: DeviceActivityMonitor {
    private let store = ManagedSettingsStore(named: .init("makeHay"))

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        // Match the legacy single-schedule name
        if activity == .makeHayTimeUnlock {
            store.clearAllSettings()
            return
        }

        // Match any per-weekday schedule name (makeHay.timeUnlock.1 … .7)
        if DeviceActivityName.allWeekdayUnlocks.contains(activity) {
            store.clearAllSettings()
        }
    }
}
