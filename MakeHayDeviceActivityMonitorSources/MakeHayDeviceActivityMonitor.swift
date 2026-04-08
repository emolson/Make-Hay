//
//  MakeHayDeviceActivityMonitor.swift
//  MakeHayDeviceActivityMonitorExtension
//
//  Created by GitHub Copilot on 2/19/26.
//

import DeviceActivity
import Foundation
import ManagedSettings
import os.log

/// Lightweight mirror of the main app's goal model, extracting only the fields
/// needed for the weekday and enabled-state guards. Keeps the extension's memory
/// footprint minimal.
private struct GoalScheduleInfo: Decodable {
    let timeBlockGoal: TimeBlockInfo?

    struct TimeBlockInfo: Decodable {
        let isEnabled: Bool
        let schedule: ScheduleInfo?

        /// Lightweight mirror of the main app's `GoalSchedule` enum.
        enum ScheduleInfo {
            case recurring(Set<Int>)
            case todayOnly(expires: Date)
        }

        private enum CodingKeys: String, CodingKey {
            case isEnabled, schedule
        }

        private enum ScheduleKeys: String, CodingKey {
            case type, weekdays, expires
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            self.isEnabled = (try? container.decode(Bool.self, forKey: .isEnabled)) ?? false

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

    private static let logger = Logger(
        subsystem: "com.ethanolson.Make-Hay",
        category: "DeviceActivityMonitor"
    )

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        guard activity == .makeHayTimeUnlock else { return }

        Self.logger.info("Time unlock interval started.")

        // Validate the time-block goal is enabled and scheduled for today.
        // **Fail-open:** if we can't read or decode the goal, clear shields anyway
        // to avoid permanently locking users out of their apps.
        if let info = Self.loadTimeBlockInfo() {
            guard info.isEnabled else {
                Self.logger.info("Time-block goal is disabled — skipping shield clear.")
                return
            }

            if let schedule = info.schedule {
                switch schedule {
                case .recurring(let days):
                    let today = Calendar.current.component(.weekday, from: Date())
                    guard days.contains(today) else {
                        Self.logger.info("Today (weekday \(today)) not in recurring schedule — skipping.")
                        return
                    }
                case .todayOnly(let expires):
                    let startOfToday = Calendar.current.startOfDay(for: Date())
                    if expires <= startOfToday {
                        Self.logger.info("One-time schedule expired — skipping shield clear.")
                        return
                    }
                }
            }
        } else {
            Self.logger.warning(
                "Could not load time-block goal info — proceeding with fail-open shield clear."
            )
        }

        store.clearAllSettings()
        Self.logger.info("Shields cleared by time unlock.")
    }

    /// Reads the time-block goal info from App Group UserDefaults.
    /// Returns `nil` when data is missing or un-decodable (triggers fail-open behavior).
    private static func loadTimeBlockInfo() -> GoalScheduleInfo.TimeBlockInfo? {
        guard let defaults = UserDefaults(suiteName: "group.ethanolson.Make-Hay") else {
            logger.error("App Group UserDefaults unavailable in extension.")
            return nil
        }

        guard let jsonString = defaults.string(forKey: "healthGoalData") else {
            logger.warning("No healthGoalData found in App Group defaults.")
            return nil
        }

        guard let data = jsonString.data(using: .utf8) else {
            logger.error("Failed to convert healthGoalData to UTF-8 data.")
            return nil
        }

        do {
            let info = try JSONDecoder().decode(GoalScheduleInfo.self, from: data)
            return info.timeBlockGoal
        } catch {
            logger.error("Failed to decode GoalScheduleInfo: \(error.localizedDescription)")
            return nil
        }
    }
}
