//
//  MakeHayDeviceActivityMonitor.swift
//  MakeHayDeviceActivityMonitorExtension
//
//  Created by GitHub Copilot on 2/19/26.
//

import DeviceActivity
import ManagedSettings

/// Device Activity monitor that performs background-resilient time unlock actions.
final class MakeHayDeviceActivityMonitor: DeviceActivityMonitor {
    private let store = ManagedSettingsStore(named: .init("makeHay"))

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        // Match any per-weekday schedule name (makeHay.timeUnlock.1 … .7)
        if DeviceActivityName.allWeekdayUnlocks.contains(activity) {
            store.clearAllSettings()
        }
    }
}
