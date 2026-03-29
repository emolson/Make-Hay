//
//  MakeHayDeviceActivityMonitor.swift
//  MakeHayDeviceActivityMonitorExtension
//
//  Created by GitHub Copilot on 2/19/26.
//

import DeviceActivity
import Foundation
import ManagedSettings

/// Lightweight mirror of the main app's goal model, extracting only the fields
/// needed for the weekday guard. Keeps the extension's memory footprint minimal.
private struct GoalScheduleInfo: Decodable {
    let timeBlockGoal: TimeBlockInfo?

    struct TimeBlockInfo: Decodable {
        let schedule: ScheduleInfo?

        /// Lightweight mirror of the main app's `GoalSchedule` enum.
        enum ScheduleInfo {
            case recurring(Set<Int>)
            case todayOnly(expires: Date)
        }

        private enum CodingKeys: String, CodingKey {
            case schedule
        }

        private enum ScheduleKeys: String, CodingKey {
            case type, weekdays, expires
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            guard let schedContainer = try? container.nestedContainer(keyedBy: ScheduleKeys.self, forKey: .schedule),
                  let type = try? schedContainer.decode(String.self, forKey: .type) else {
                self.schedule = nil
                return
            }

            switch type {
            case "recurring":
                let days = (try? schedContainer.decode(Set<Int>.self, forKey: .weekdays)) ?? []
                self.schedule = .recurring(days)
            case "todayOnly":
                let expires = try schedContainer.decode(Date.self, forKey: .expires)
                self.schedule = .todayOnly(expires: expires)
            default:
                self.schedule = nil
            }
        }
    }
}

/// Device Activity monitor that performs background-resilient time unlock actions.
final class MakeHayDeviceActivityMonitor: DeviceActivityMonitor {
    private let store = ManagedSettingsStore(named: .init("makeHay"))

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        guard activity == .makeHayTimeUnlock else { return }

        // Check if today's weekday is in the time-block goal's schedule.
        // **Fail-open:** if we can't read or decode the goal, clear shields anyway
        // to avoid permanently locking users out of their apps.
        if let info = Self.loadTimeBlockInfo(),
           let schedule = info.schedule {
            switch schedule {
            case .recurring(let days):
                let today = Calendar.current.component(.weekday, from: Date())
                guard days.contains(today) else { return }
            case .todayOnly(let expires):
                let startOfToday = Calendar.current.startOfDay(for: Date())
                if expires <= startOfToday { return } // Expired — do not clear shields
            }
        }

        store.clearAllSettings()
    }

    /// Reads the time-block goal info from App Group UserDefaults.
    /// Returns `nil` when data is missing or un-decodable (triggers fail-open behavior).
    private static func loadTimeBlockInfo() -> GoalScheduleInfo.TimeBlockInfo? {
        guard let defaults = UserDefaults(suiteName: "group.ethanolson.Make-Hay"),
              let jsonString = defaults.string(forKey: "healthGoalData"),
              let data = jsonString.data(using: .utf8),
              let info = try? JSONDecoder().decode(GoalScheduleInfo.self, from: data)
        else { return nil }

        return info.timeBlockGoal
    }
}
