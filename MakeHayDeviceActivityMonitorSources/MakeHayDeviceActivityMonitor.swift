//
//  MakeHayDeviceActivityMonitor.swift
//  MakeHayDeviceActivityMonitorExtension
//
//  Created by GitHub Copilot on 2/19/26.
//

@preconcurrency import DeviceActivity
import FamilyControls
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

            guard
                let schedContainer = try? container.nestedContainer(
                    keyedBy: ScheduleKeys.self, forKey: .schedule),
                let type = try? schedContainer.decode(String.self, forKey: .type)
            else {
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

/// Result of loading the persisted blocked-app selection from the App Group container.
private enum PersistedSelectionLoadResult {
    case loaded(FamilyActivitySelection)
    case missing
    case decodeFailed
    case appGroupUnavailable
}

/// Device Activity monitor that performs background-resilient time unlock actions.
///
/// **Isolation:** DeviceActivity delivers callbacks on arbitrary background threads.
/// All overrides are explicitly `nonisolated`. The stored `ManagedSettingsStore` is
/// `Sendable` and the static logger is safe for concurrent access, so no actor hop
/// is needed.
final class MakeHayDeviceActivityMonitor: DeviceActivityMonitor {
    nonisolated private let store = ManagedSettingsStore(named: .init("makeHay"))

    nonisolated private static let logger = Logger(
        subsystem: "com.ethanolson.Make-Hay",
        category: "DeviceActivityMonitor"
    )

    nonisolated override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        if activity == .makeHayPeekEnd {
            handlePeekEnd()
            return
        }

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
                        Self.logger.info(
                            "Recurring schedule inactive today; skipping shield clear.")
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

    /// Called when the time-unlock interval ends (23:59 daily).
    ///
    /// **Why re-shield here?** Without this, apps stay unshielded until the main app's
    /// next background evaluation — which may be delayed by iOS throttling. Re-applying
    /// shields at interval end ensures the block state is restored promptly.
    ///
    /// **Fail-closed:** If the persisted selection can't be loaded, we log a warning
    /// but do nothing (shields stay cleared). This is intentional — re-shielding with
    /// stale or empty data could lock the user out without recourse.
    nonisolated override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        guard activity == .makeHayTimeUnlock else { return }

        Self.logger.info("Time unlock interval ended.")

        // Don't re-shield if a Mindful Peek is currently active — the peek timer
        // (or its DeviceActivity monitor) will re-apply shields when it expires.
        if let defaults = UserDefaults(suiteName: "group.ethanolson.Make-Hay") {
            let peekExpiration = defaults.double(forKey: peekExpirationDateKey)
            if peekExpiration > 0 && Date().timeIntervalSince1970 < peekExpiration {
                Self.logger.info("Mindful Peek is active — skipping re-shield at interval end.")
                return
            }
        }

        // Only re-shield if the time-block goal is still enabled and scheduled today.
        guard let info = Self.loadTimeBlockInfo(), info.isEnabled else {
            Self.logger.info("Time-block goal disabled or unreadable — skipping re-shield.")
            return
        }

        // Same schedule guard used by intervalDidStart — the DeviceActivity schedule
        // repeats daily, so we must skip re-shielding on days the goal is inactive.
        if let schedule = info.schedule {
            switch schedule {
            case .recurring(let days):
                let today = Calendar.current.component(.weekday, from: Date())
                guard days.contains(today) else {
                    Self.logger.info("Recurring schedule inactive today; skipping re-shield.")
                    return
                }
            case .todayOnly(let expires):
                let startOfToday = Calendar.current.startOfDay(for: Date())
                if expires <= startOfToday {
                    Self.logger.info("One-time schedule expired — skipping re-shield.")
                    return
                }
            }
        }

        switch Self.loadPersistedSelection() {
        case .loaded(let selection):
            applyShields(from: selection)
        case .missing:
            Self.logger.warning("No persisted app selection found — cannot re-shield.")
            return
        case .decodeFailed:
            Self.logger.error("Failed to decode persisted blocked-app selection.")
            return
        case .appGroupUnavailable:
            Self.logger.error("App Group container URL unavailable in extension.")
            return
        }

        Self.logger.info("Shields re-applied after time unlock interval ended.")
    }

    // MARK: - Mindful Peek End

    /// Re-applies shields when the Mindful Peek timer expires.
    ///
    /// **Fail-closed:** If the persisted selection can't be loaded, shields stay cleared
    /// but the next background health evaluation will re-block. We nil the expiration
    /// date in SharedStorage so `isPeekActive` returns false and the foreground app
    /// (if open) also re-blocks.
    nonisolated private func handlePeekEnd() {
        Self.logger.info("Peek-end interval started — re-applying shields.")

        // Expire the peek in SharedStorage so both the app and future evaluations
        // know the peek is over.
        guard let defaults = UserDefaults(suiteName: "group.ethanolson.Make-Hay") else {
            Self.logger.error("App Group UserDefaults unavailable — cannot expire peek.")
            return
        }
        defaults.removeObject(forKey: peekExpirationDateKey)

        switch Self.loadPersistedSelection() {
        case .loaded(let selection):
            applyShields(from: selection)
            Self.recordPeekRestore(defaults: defaults, outcome: "applied")
        case .missing:
            Self.recordPeekRestore(
                defaults: defaults,
                outcome: "failed",
                failure: "selectionMissing"
            )
            Self.logger.warning(
                "No persisted app selection — cannot re-shield after peek. Next evaluation will re-block."
            )
            return
        case .decodeFailed:
            Self.recordPeekRestore(
                defaults: defaults,
                outcome: "failed",
                failure: "selectionDecodeFailed"
            )
            Self.logger.error("Failed to decode persisted blocked-app selection.")
            return
        case .appGroupUnavailable:
            Self.recordPeekRestore(
                defaults: defaults,
                outcome: "failed",
                failure: "appGroupUnavailable"
            )
            Self.logger.error("App Group container URL unavailable in extension.")
            return
        }

        Self.logger.info("Shields re-applied after Mindful Peek expired.")
    }

    /// Applies the persisted block selection to the shared ManagedSettings store.
    /// Empty app or category sets explicitly clear that dimension so stale shields
    /// from older selections cannot linger.
    nonisolated private func applyShields(from selection: FamilyActivitySelection) {
        store.shield.applications =
            selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens
        store.shield.applicationCategories =
            selection.categoryTokens.isEmpty
            ? nil
            : ShieldSettings.ActivityCategoryPolicy.specific(
                selection.categoryTokens,
                except: Set()
            )
    }

    /// Records the latest coarse peek-expiry enforcement event for the app to inspect.
    nonisolated private static func recordPeekRestore(
        defaults: UserDefaults,
        outcome: String,
        failure: String? = nil
    ) {
        defaults.set(Date().timeIntervalSince1970, forKey: peekRestoreEventDateKey)
        defaults.set("extension", forKey: peekRestoreSourceKey)
        defaults.set(outcome, forKey: peekRestoreOutcomeKey)
        if let failure {
            defaults.set(failure, forKey: peekRestoreFailureKey)
        } else {
            defaults.removeObject(forKey: peekRestoreFailureKey)
        }
    }

    /// Reads the time-block goal info from App Group UserDefaults.
    /// Returns `nil` when data is missing or un-decodable (triggers fail-open behavior).
    nonisolated private static func loadTimeBlockInfo() -> GoalScheduleInfo.TimeBlockInfo? {
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
            let _ = error
            logger.error("Failed to decode time-block goal state.")
            return nil
        }
    }

    /// Reads the persisted `FamilyActivitySelection` from the App Group container.
    ///
    /// **Why load from disk?** The extension runs in a separate process and cannot access
    /// `BlockerService`'s in-memory selection. The main app persists the selection as a
    /// PropertyList file in the shared App Group container, which the extension reads here.
    nonisolated private static func loadPersistedSelection() -> PersistedSelectionLoadResult {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.ethanolson.Make-Hay"
            )
        else {
            return .appGroupUnavailable
        }

        let selectionURL = containerURL.appendingPathComponent("FamilyActivitySelection.plist")

        guard FileManager.default.fileExists(atPath: selectionURL.path) else {
            return .missing
        }

        do {
            let data = try Data(contentsOf: selectionURL)
            let selection = try PropertyListDecoder().decode(
                FamilyActivitySelection.self, from: data)
            return .loaded(selection)
        } catch {
            return .decodeFailed
        }
    }
}
