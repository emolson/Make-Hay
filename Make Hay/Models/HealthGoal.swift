//
//  HealthGoal.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import Foundation
import HealthKit

/// Days of the week used for goal repeat scheduling.
/// **Why Int raw values starting at 1?** Matches `Calendar.current.component(.weekday)`,
/// where Sunday = 1 ... Saturday = 7, enabling direct comparison without mapping.
enum Weekday: Int, Codable, Sendable, CaseIterable, Identifiable, Comparable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }

    /// Short display name (e.g. "Mon").
    var shortName: String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return symbols[rawValue - 1]
    }

    /// Full display name (e.g. "Monday").
    var fullName: String {
        let symbols = Calendar.current.weekdaySymbols
        return symbols[rawValue - 1]
    }

    /// The current weekday based on the user's calendar.
    static var today: Weekday {
        let component = Calendar.current.component(.weekday, from: Date())
        return Weekday(rawValue: component) ?? .sunday
    }

    /// Ordered cases starting with Monday for display purposes.
    static var orderedCases: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }

    nonisolated static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Describes when a goal is active.
///
/// **Why an enum instead of `Set<Weekday>` + `expirationDate: Date?`?**
/// The previous design used an empty set as a magic sentinel for "today only"
/// and required a separate `expirationDate` field that had to stay in sync.
/// This enum makes the two cases explicit and compiler-enforced — impossible
/// states (empty set without expiration, recurring with expiration) are
/// unrepresentable.
enum GoalSchedule: Sendable, Equatable {
    /// Repeats on the specified weekdays (must be non-empty).
    case recurring(Set<Weekday>)
    /// Active today only; auto-disables after `expires`.
    case todayOnly(expires: Date)

    // MARK: - Convenience Factories

    /// All seven days.
    static let everyDay: GoalSchedule = .recurring(Set(Weekday.allCases))
    /// Monday through Friday.
    static let weekdays: GoalSchedule = .recurring([.monday, .tuesday, .wednesday, .thursday, .friday])
    /// Saturday and Sunday.
    static let weekends: GoalSchedule = .recurring([.saturday, .sunday])

    // MARK: - Queries

    /// Whether this schedule includes today's weekday.
    /// A `.todayOnly` schedule always includes today (the expiration check is
    /// handled separately by `expireGoalsIfNeeded`).
    var includestoday: Bool {
        switch self {
        case .recurring(let days): return days.contains(Weekday.today)
        case .todayOnly: return true
        }
    }

    /// Constructs a `GoalSchedule` from a picker's day selection.
    /// An empty set becomes `.todayOnly` with expiration at start-of-tomorrow.
    static func from(weekdays: Set<Weekday>) -> GoalSchedule {
        if weekdays.isEmpty {
            let tomorrow = Calendar.current.startOfDay(
                for: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            )
            return .todayOnly(expires: tomorrow)
        }
        return .recurring(weekdays)
    }

    /// Human-readable summary for display in the UI.
    var displaySummary: String {
        switch self {
        case .recurring(let days):
            let all = Set(Weekday.allCases)
            let wkdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
            let wkends: Set<Weekday> = [.saturday, .sunday]
            if days == all { return String(localized: "Every day") }
            if days == wkdays { return String(localized: "Weekdays") }
            if days == wkends { return String(localized: "Weekends") }
            return Weekday.orderedCases
                .filter { days.contains($0) }
                .map(\.shortName)
                .joined(separator: ", ")
        case .todayOnly:
            return String(localized: "Today only")
        }
    }

    /// The raw weekday set, or an empty set for `.todayOnly`.
    /// Useful for pre-filling the day picker when editing a goal.
    var weekdays: Set<Weekday> {
        switch self {
        case .recurring(let days): return days
        case .todayOnly: return []
        }
    }

    /// The expiration date, if this is a `.todayOnly` schedule.
    var expirationDate: Date? {
        switch self {
        case .recurring: return nil
        case .todayOnly(let expires): return expires
        }
    }
}

// MARK: - Codable

extension GoalSchedule: Codable {
    /// **Encoding format:**
    /// - `.recurring`: `{"type": "recurring", "weekdays": [1,2,3,...]}`
    /// - `.todayOnly`: `{"type": "todayOnly", "expires": <date>}`
    private enum CodingKeys: String, CodingKey {
        case type, weekdays, expires
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "recurring":
            let days = try container.decode(Set<Weekday>.self, forKey: .weekdays)
            self = .recurring(days)
        case "todayOnly":
            let expires = try container.decode(Date.self, forKey: .expires)
            self = .todayOnly(expires: expires)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown GoalSchedule type: \(type)"
            )
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .recurring(let days):
            try container.encode("recurring", forKey: .type)
            try container.encode(days, forKey: .weekdays)
        case .todayOnly(let expires):
            try container.encode("todayOnly", forKey: .type)
            try container.encode(expires, forKey: .expires)
        }
    }
}

/// Model representing a user's daily health goal configuration.
struct HealthGoal: Codable, Sendable, Equatable {
    /// The user's step goal configuration.
    var stepGoal: StepGoal = .init()
    /// The user's active energy goal configuration.
    var activeEnergyGoal: ActiveEnergyGoal = .init()
    /// The user's exercise goal configurations (supports multiple exercise types).
    var exerciseGoals: [ExerciseGoal] = []
    /// The user's time-based unlock goal configuration.
    var timeBlockGoal: TimeBlockGoal = .init()
    /// Strategy for determining when goals unlock apps.
    var blockingStrategy: BlockingStrategy = .all
    
    // MARK: - Pending Changes (Per-Goal)
    
    /// Pending step goal change scheduled to take effect at `pendingGoalEffectiveDate`.
    /// `nil` means no pending change for this goal type.
    var pendingStepGoal: StepGoal?
    /// Pending active energy goal change.
    var pendingActiveEnergyGoal: ActiveEnergyGoal?
    /// Pending exercise goal changes, matched by ID.
    /// Only exercise goals that were actually edited appear here.
    var pendingExerciseGoals: [ExerciseGoal] = []
    /// IDs of exercise goals scheduled for deletion at `pendingGoalEffectiveDate`.
    /// **Why separate from `pendingExerciseGoals`?** Edits store a full `ExerciseGoal`
    /// to replace by ID, but deletions have no replacement object. A dedicated set
    /// avoids conflating "disabled" with "deleted" and keeps intent explicit.
    var pendingExerciseGoalDeletions: Set<UUID> = []
    /// Pending time-block goal change.
    var pendingTimeBlockGoal: TimeBlockGoal?
    
    /// The date when pending changes should take effect (midnight of next day).
    /// **Why Date?** Allows precise comparison to determine when to apply changes.
    var pendingGoalEffectiveDate: Date?
    
    /// Whether any per-goal pending changes exist.
    var hasPendingChanges: Bool {
        pendingStepGoal != nil
            || pendingActiveEnergyGoal != nil
            || !pendingExerciseGoals.isEmpty
            || !pendingExerciseGoalDeletions.isEmpty
            || pendingTimeBlockGoal != nil
    }

    nonisolated init(
        stepGoal: StepGoal = .init(),
        activeEnergyGoal: ActiveEnergyGoal = .init(),
        exerciseGoals: [ExerciseGoal] = [],
        timeBlockGoal: TimeBlockGoal = .init(),
        blockingStrategy: BlockingStrategy = .all,
        pendingStepGoal: StepGoal? = nil,
        pendingActiveEnergyGoal: ActiveEnergyGoal? = nil,
        pendingExerciseGoals: [ExerciseGoal] = [],
        pendingExerciseGoalDeletions: Set<UUID> = [],
        pendingTimeBlockGoal: TimeBlockGoal? = nil,
        pendingGoalEffectiveDate: Date? = nil
    ) {
        self.stepGoal = stepGoal
        self.activeEnergyGoal = activeEnergyGoal
        self.exerciseGoals = exerciseGoals
        self.timeBlockGoal = timeBlockGoal
        self.blockingStrategy = blockingStrategy
        self.pendingStepGoal = pendingStepGoal
        self.pendingActiveEnergyGoal = pendingActiveEnergyGoal
        self.pendingExerciseGoals = pendingExerciseGoals
        self.pendingExerciseGoalDeletions = pendingExerciseGoalDeletions
        self.pendingTimeBlockGoal = pendingTimeBlockGoal
        self.pendingGoalEffectiveDate = pendingGoalEffectiveDate
    }
    
    /// Applies pending goal changes if the effective date has passed.
    /// Each per-goal pending field is applied independently and then cleared.
    /// - Returns: True if any pending changes were applied.
    @discardableResult
    mutating func applyPendingIfReady() -> Bool {
        guard hasPendingChanges,
              let effectiveDate = pendingGoalEffectiveDate,
              Date() >= effectiveDate else {
            return false
        }
        
        if let pending = pendingStepGoal {
            self.stepGoal = pending
        }
        if let pending = pendingActiveEnergyGoal {
            self.activeEnergyGoal = pending
        }
        for pendingExercise in pendingExerciseGoals {
            if let index = exerciseGoals.firstIndex(where: { $0.id == pendingExercise.id }) {
                exerciseGoals[index] = pendingExercise
            }
        }
        // Apply deferred exercise-goal deletions
        if !pendingExerciseGoalDeletions.isEmpty {
            exerciseGoals.removeAll { pendingExerciseGoalDeletions.contains($0.id) }
        }
        if let pending = pendingTimeBlockGoal {
            self.timeBlockGoal = pending
        }
        
        // Clear all pending state
        clearPendingChanges()
        
        return true
    }
    
    /// Clears all per-goal pending changes and the effective date.
    mutating func clearPendingChanges() {
        pendingStepGoal = nil
        pendingActiveEnergyGoal = nil
        pendingExerciseGoals = []
        pendingExerciseGoalDeletions = []
        pendingTimeBlockGoal = nil
        pendingGoalEffectiveDate = nil
    }

    /// Disables any enabled goal whose `.todayOnly` schedule has expired.
    ///
    /// **Why per sub-goal?** Each goal can have an independent "today only" schedule
    /// with its own expiration. Checking all four types ensures no stale one-time goal
    /// persists after midnight.
    ///
    /// - Parameter now: The reference date (defaults to `Date()`; injectable for tests).
    /// - Returns: `true` if any goal was expired and disabled.
    @discardableResult
    mutating func expireGoalsIfNeeded(now: Date = Date()) -> Bool {
        var changed = false

        if stepGoal.isEnabled, case .todayOnly(let exp) = stepGoal.schedule, now >= exp {
            stepGoal.isEnabled = false
            stepGoal.schedule = .everyDay
            changed = true
        }
        if activeEnergyGoal.isEnabled, case .todayOnly(let exp) = activeEnergyGoal.schedule, now >= exp {
            activeEnergyGoal.isEnabled = false
            activeEnergyGoal.schedule = .everyDay
            changed = true
        }
        for index in exerciseGoals.indices {
            if exerciseGoals[index].isEnabled,
               case .todayOnly(let exp) = exerciseGoals[index].schedule,
               now >= exp {
                exerciseGoals[index].isEnabled = false
                exerciseGoals[index].schedule = .everyDay
                changed = true
            }
        }
        if timeBlockGoal.isEnabled, case .todayOnly(let exp) = timeBlockGoal.schedule, now >= exp {
            timeBlockGoal.isEnabled = false
            timeBlockGoal.schedule = .everyDay
            changed = true
        }

        return changed
    }

    private enum CodingKeys: String, CodingKey {
        case stepGoal
        case activeEnergyGoal
        case exerciseGoals
        case timeBlockGoal
        case blockingStrategy
        case pendingStepGoal
        case pendingActiveEnergyGoal
        case pendingExerciseGoals
        case pendingExerciseGoalDeletions
        case pendingTimeBlockGoal
        case pendingGoalEffectiveDate
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.init(
            stepGoal: try container.decodeIfPresent(StepGoal.self, forKey: .stepGoal) ?? .init(),
            activeEnergyGoal: try container.decodeIfPresent(ActiveEnergyGoal.self, forKey: .activeEnergyGoal) ?? .init(),
            exerciseGoals: try container.decodeIfPresent([ExerciseGoal].self, forKey: .exerciseGoals) ?? [],
            timeBlockGoal: try container.decodeIfPresent(TimeBlockGoal.self, forKey: .timeBlockGoal) ?? .init(),
            blockingStrategy: try container.decodeIfPresent(BlockingStrategy.self, forKey: .blockingStrategy) ?? .all,
            pendingStepGoal: try container.decodeIfPresent(StepGoal.self, forKey: .pendingStepGoal),
            pendingActiveEnergyGoal: try container.decodeIfPresent(ActiveEnergyGoal.self, forKey: .pendingActiveEnergyGoal),
            pendingExerciseGoals: try container.decodeIfPresent([ExerciseGoal].self, forKey: .pendingExerciseGoals) ?? [],
            pendingExerciseGoalDeletions: try container.decodeIfPresent(Set<UUID>.self, forKey: .pendingExerciseGoalDeletions) ?? [],
            pendingTimeBlockGoal: try container.decodeIfPresent(TimeBlockGoal.self, forKey: .pendingTimeBlockGoal),
            pendingGoalEffectiveDate: try container.decodeIfPresent(Date.self, forKey: .pendingGoalEffectiveDate)
        )
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stepGoal, forKey: .stepGoal)
        try container.encode(activeEnergyGoal, forKey: .activeEnergyGoal)
        try container.encode(exerciseGoals, forKey: .exerciseGoals)
        try container.encode(timeBlockGoal, forKey: .timeBlockGoal)
        try container.encode(blockingStrategy, forKey: .blockingStrategy)
        try container.encodeIfPresent(pendingStepGoal, forKey: .pendingStepGoal)
        try container.encodeIfPresent(pendingActiveEnergyGoal, forKey: .pendingActiveEnergyGoal)
        if !pendingExerciseGoals.isEmpty {
            try container.encode(pendingExerciseGoals, forKey: .pendingExerciseGoals)
        }
        if !pendingExerciseGoalDeletions.isEmpty {
            try container.encode(pendingExerciseGoalDeletions, forKey: .pendingExerciseGoalDeletions)
        }
        try container.encodeIfPresent(pendingTimeBlockGoal, forKey: .pendingTimeBlockGoal)
        try container.encodeIfPresent(pendingGoalEffectiveDate, forKey: .pendingGoalEffectiveDate)
    }

    // MARK: - Persistence

    nonisolated static let storageKey: String = "healthGoalData"

    /// Loads the health goal from App Group `UserDefaults`.
    nonisolated static func load(from defaults: UserDefaults = SharedStorage.appGroupDefaults) -> HealthGoal {
        if let dataString = defaults.string(forKey: storageKey),
           let data = dataString.data(using: .utf8),
           let goal = try? JSONDecoder().decode(HealthGoal.self, from: data) {
            return goal
        }
        return HealthGoal()
    }

    /// Saves the health goal to App Group `UserDefaults`.
    nonisolated static func save(_ goal: HealthGoal, to defaults: UserDefaults = SharedStorage.appGroupDefaults) {
        guard let data = try? JSONEncoder().encode(goal),
              let encoded = String(data: data, encoding: .utf8) else { return }
        defaults.set(encoded, forKey: storageKey)
    }
}

/// Snapshot input used by `GoalBlockingEvaluator` to make a gate decision.
///
/// **Why this type?** Keeps gate logic pure and reusable across Dashboard and
/// Settings without coupling to a specific ViewModel.
struct GoalEvaluationSnapshot: Sendable {
    var steps: Int
    var activeEnergy: Double
    var exerciseMinutesByGoalId: [UUID: Int]
    var currentMinutesSinceMidnight: Int
}

/// Shared evaluator for determining whether goals are currently met.
///
/// **Why centralize this logic?** Goal edit gating and blocked-app edit gating
/// must stay perfectly aligned so users cannot bypass one flow via another.
enum GoalBlockingEvaluator {
    /// Returns whether any goal is enabled in the provided configuration.
    nonisolated static func hasEnabledGoals(goal: HealthGoal) -> Bool {
        goal.stepGoal.isEnabled
            || goal.activeEnergyGoal.isEnabled
            || goal.exerciseGoals.contains(where: { $0.isEnabled })
            || goal.timeBlockGoal.isEnabled
    }

    /// Returns whether the configured goals are met for the provided snapshot.
    nonisolated static func isGoalMet(goal: HealthGoal, snapshot: GoalEvaluationSnapshot) -> Bool {
        let progresses = goalProgresses(goal: goal, snapshot: snapshot)
        guard !progresses.isEmpty else { return true }
        return progresses.allSatisfy { $0 }
    }

    /// Returns whether apps should currently be blocked.
    nonisolated static func shouldBlock(goal: HealthGoal, snapshot: GoalEvaluationSnapshot) -> Bool {
        let enabledGoals = goalProgresses(goal: goal, snapshot: snapshot)
        guard !enabledGoals.isEmpty else { return false }
        return !isGoalMet(goal: goal, snapshot: snapshot)
    }

    /// Returns whether easier edits should be deferred behind the pending-change flow.
    ///
    /// **Why separate from `shouldBlock`?** Deferral gate logic is intentionally
    /// decoupled from blocking logic so each can evolve independently. All enabled
    /// goals must be met before the user is permitted to weaken their commitments.
    nonisolated static func shouldDeferChanges(goal: HealthGoal, snapshot: GoalEvaluationSnapshot) -> Bool {
        let progresses = goalProgresses(goal: goal, snapshot: snapshot)
        guard !progresses.isEmpty else { return false }
        // Strict: ALL enabled goals must be met before edits are allowed
        return !progresses.allSatisfy { $0 }
    }

    private nonisolated static func goalProgresses(goal: HealthGoal, snapshot: GoalEvaluationSnapshot) -> [Bool] {
        var progresses: [Bool] = []

        if goal.stepGoal.isEnabled && goal.stepGoal.schedule.includestoday {
            progresses.append(snapshot.steps >= goal.stepGoal.target)
        }

        if goal.activeEnergyGoal.isEnabled && goal.activeEnergyGoal.schedule.includestoday {
            progresses.append(snapshot.activeEnergy >= Double(goal.activeEnergyGoal.target))
        }

        for exerciseGoal in goal.exerciseGoals where exerciseGoal.isEnabled && exerciseGoal.schedule.includestoday {
            let current = snapshot.exerciseMinutesByGoalId[exerciseGoal.id] ?? 0
            progresses.append(current >= exerciseGoal.targetMinutes)
        }

        if goal.timeBlockGoal.isEnabled && goal.timeBlockGoal.schedule.includestoday {
            let isMet = goal.timeBlockGoal.clampedUnlockMinutes == 0
                || snapshot.currentMinutesSinceMidnight >= goal.timeBlockGoal.clampedUnlockMinutes
            progresses.append(isMet)
        }

        return progresses
    }
}

/// Shared gatekeeper used by multiple features before applying easier edits.
///
/// **Policy:** If fresh health reads fail, default to deferral so users cannot
/// bypass goal guards due to transient fetch failures.
enum GoalGatekeeper {
    nonisolated static func shouldDeferEdits(
        goal: HealthGoal,
        healthService: any HealthServiceProtocol,
        now: Date = Date()
    ) async -> Bool {
        do {
            let currentData = try await healthService.fetchCurrentData()
            let exerciseMinutes = try await fetchExerciseMinutesByGoalId(
                goal: goal,
                healthService: healthService
            )
            let snapshot = GoalEvaluationSnapshot(
                steps: currentData.steps,
                activeEnergy: currentData.activeEnergy,
                exerciseMinutesByGoalId: exerciseMinutes,
                currentMinutesSinceMidnight: currentMinutesSinceMidnight(date: now)
            )

            return GoalBlockingEvaluator.shouldDeferChanges(goal: goal, snapshot: snapshot)
        } catch {
            return true
        }
    }

    private nonisolated static func fetchExerciseMinutesByGoalId(
        goal: HealthGoal,
        healthService: any HealthServiceProtocol
    ) async throws -> [UUID: Int] {
        var result: [UUID: Int] = [:]

        for exerciseGoal in goal.exerciseGoals where exerciseGoal.isEnabled {
            let minutes = try await healthService.fetchExerciseMinutes(
                for: exerciseGoal.exerciseType.hkWorkoutActivityType
            )
            result[exerciseGoal.id] = minutes
        }

        return result
    }

    private nonisolated static func currentMinutesSinceMidnight(date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

/// Configuration for a steps goal.
struct StepGoal: Codable, Sendable, Equatable {
    var isEnabled: Bool = true
    var target: Int = 8_000
    var schedule: GoalSchedule = .everyDay

    nonisolated init(isEnabled: Bool = true, target: Int = 8_000, schedule: GoalSchedule = .everyDay) {
        self.isEnabled = isEnabled
        self.target = target
        self.schedule = schedule
    }
}

/// Configuration for an active energy (calories) goal.
struct ActiveEnergyGoal: Codable, Sendable, Equatable {
    var isEnabled: Bool = false
    var target: Int = 500
    var schedule: GoalSchedule = .everyDay

    nonisolated init(isEnabled: Bool = false, target: Int = 500, schedule: GoalSchedule = .everyDay) {
        self.isEnabled = isEnabled
        self.target = target
        self.schedule = schedule
    }
}

/// Configuration for an exercise minutes goal.
struct ExerciseGoal: Codable, Sendable, Equatable, Identifiable {
    var id: UUID = UUID()
    var isEnabled: Bool = true
    var targetMinutes: Int = 30
    var exerciseType: ExerciseType = .any
    var schedule: GoalSchedule = .everyDay

    nonisolated init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        targetMinutes: Int = 30,
        exerciseType: ExerciseType = .any,
        schedule: GoalSchedule = .everyDay
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.targetMinutes = targetMinutes
        self.exerciseType = exerciseType
        self.schedule = schedule
    }
}

/// Configuration for a time-based unlock goal.
/// Stores the unlock time as minutes since midnight.
///
/// **Midnight Edge Case:** If `unlockTimeMinutes` is 0 (midnight), the goal is
/// considered instantly met, meaning apps are never blocked. This allows users
/// to effectively disable time-based blocking while keeping the goal enabled.
struct TimeBlockGoal: Codable, Sendable, Equatable {
    var isEnabled: Bool = false
    /// Minutes since midnight (0-1439). Default is 7 PM (19:00).
    var unlockTimeMinutes: Int = 19 * 60
    var schedule: GoalSchedule = .everyDay

    nonisolated init(isEnabled: Bool = false, unlockTimeMinutes: Int = 19 * 60, schedule: GoalSchedule = .everyDay) {
        self.isEnabled = isEnabled
        self.unlockTimeMinutes = unlockTimeMinutes
        self.schedule = schedule
    }
}

/// Defines when apps unlock relative to enabled goals.
enum BlockingStrategy: String, Codable, Sendable {
    case all
}

/// Supported exercise types for filtering workouts.
enum ExerciseType: String, Codable, CaseIterable, Sendable, Identifiable {
    case any
    case americanFootball
    case archery
    case australianFootball
    case badminton
    case barre
    case baseball
    case basketball
    case bowling
    case boxing
    case cardioDance
    case climbing
    case cooldown
    case coreTraining
    case cricket
    case crossCountrySkiing
    case crossTraining
    case curling
    case cycling
    case discSports
    case downhillSkiing
    case elliptical
    case equestrianSports
    case fencing
    case fishing
    case fitnessGaming
    case flexibility
    case functionalStrengthTraining
    case golf
    case gymnastics
    case handCycling
    case handball
    case hiit
    case hiking
    case hockey
    case hunting
    case jumpRope
    case kickboxing
    case lacrosse
    case martialArts
    case mindAndBody
    case mixedCardio
    case paddleSports
    case pickleball
    case pilates
    case play
    case preparationAndRecovery
    case racquetball
    case rowing
    case rugby
    case running
    case sailing
    case skatingSports
    case snowSports
    case snowboarding
    case soccer
    case socialDance
    case softball
    case squash
    case stairClimbing
    case stairs
    case stepTraining
    case strengthTraining
    case surfingSports
    case swimBikeRun
    case swimming
    case tableTennis
    case taiChi
    case tennis
    case trackAndField
    case transition
    case underwaterDiving
    case volleyball
    case walking
    case waterFitness
    case waterPolo
    case waterSports
    case wheelchairRunPace
    case wheelchairWalkPace
    case wrestling
    case yoga
    case other

    // **Why no manual `allCases`?** Swift's automatic `CaseIterable` synthesis
    // generates `allCases` from the enum declaration order. Overriding it with a
    // manual array is a maintenance trap — adding a new case without updating the
    // manual list would silently hide it from the UI picker. Removing the override
    // lets the compiler keep the list in sync automatically.
    
    var id: String { rawValue }
    
    var displayName: String {
        Self.displayNames[self] ?? "Unknown"
    }
    
    var iconName: String {
        switch self {
case .any: return "figure.mixed.cardio"
        case .americanFootball: return "figure.american.football"
        case .archery: return "figure.archery"
        case .australianFootball: return "figure.australian.football"
        case .badminton: return "figure.badminton"
        case .barre: return "figure.barre"
        case .baseball: return "figure.baseball"
        case .basketball: return "figure.basketball"
        case .bowling: return "figure.bowling"
        case .boxing: return "figure.boxing"
        case .cardioDance: return "figure.dance"
        case .climbing: return "figure.climbing"
        case .coreTraining: return "figure.core.training"
        case .cricket: return "figure.cricket"
        case .crossCountrySkiing: return "figure.skiing.crosscountry"
        case .crossTraining: return "figure.strengthtraining.functional"
        case .curling: return "figure.curling"
        case .cycling: return "figure.outdoor.cycle"
        case .discSports: return "figure.disc.sports"
        case .downhillSkiing: return "figure.skiing.downhill"
        case .elliptical: return "figure.elliptical"
        case .equestrianSports: return "figure.equestrian.sports"
        case .fencing: return "figure.fencing"
        case .fishing: return "figure.fishing"
        case .fitnessGaming: return "gamecontroller.fill"
        case .flexibility: return "figure.flexibility"
        case .functionalStrengthTraining: return "figure.strengthtraining.functional"
        case .golf: return "figure.golf"
        case .gymnastics: return "figure.gymnastics"
        case .handball: return "figure.handball"
        case .handCycling: return "figure.hand.cycling"
        case .hiit: return "figure.highintensity.intervaltraining"
        case .hiking: return "figure.hiking"
        case .hockey: return "figure.hockey"
        case .hunting: return "figure.hunting"
        case .jumpRope: return "figure.jumprope"
        case .kickboxing: return "figure.kickboxing"
        case .lacrosse: return "figure.lacrosse"
        case .martialArts: return "figure.martial.arts"
        case .mindAndBody, .yoga: return "figure.yoga"
        case .mixedCardio: return "figure.mixed.cardio"
        case .paddleSports, .waterSports: return "figure.open.water.swim"
        case .pickleball: return "figure.pickleball"
        case .pilates: return "figure.pilates"
        case .play: return "figure.play"
        case .preparationAndRecovery, .cooldown: return "figure.cooldown"
        case .racquetball: return "figure.racquetball"
        case .rowing: return "figure.rower"
        case .rugby: return "figure.rugby"
        case .running: return "figure.run"
        case .sailing: return "figure.sailing"
        case .skatingSports: return "figure.skating"
        case .snowboarding: return "figure.snowboarding"
        case .snowSports: return "snowflake"
        case .soccer: return "figure.soccer"
        case .socialDance: return "figure.socialdance"
        case .softball: return "figure.softball"
        case .squash: return "figure.squash"
        case .stairClimbing, .stairs: return "figure.stair.stepper"
        case .stepTraining: return "figure.step.training"
        case .strengthTraining: return "figure.strengthtraining.traditional"
        case .surfingSports: return "figure.surfing"
        case .swimBikeRun, .transition: return "figure.mixed.cardio"
        case .swimming, .underwaterDiving: return "figure.pool.swim"
        case .tableTennis: return "figure.table.tennis"
        case .taiChi: return "figure.taichi"
        case .tennis: return "figure.tennis"
        case .trackAndField: return "figure.track.and.field"
        case .volleyball: return "figure.volleyball"
        case .walking: return "figure.walk"
        case .waterFitness: return "figure.water.fitness"
        case .waterPolo: return "figure.waterpolo"
        case .wheelchairWalkPace, .wheelchairRunPace: return "figure.roll"
        case .wrestling: return "figure.wrestling"
        case .other: return "figure.mixed.cardio"
        }
    }
    
    nonisolated var hkWorkoutActivityType: HKWorkoutActivityType? {
        switch self {
case .any:
            return nil
        case .americanFootball:
            return .americanFootball
        case .archery:
            return .archery
        case .australianFootball:
            return .australianFootball
        case .badminton:
            return .badminton
        case .barre:
            return .barre
        case .baseball:
            return .baseball
        case .basketball:
            return .basketball
        case .bowling:
            return .bowling
        case .boxing:
            return .boxing
        case .cardioDance:
            return .cardioDance
        case .climbing:
            return .climbing
        case .cooldown:
            return .cooldown
        case .coreTraining:
            return .coreTraining
        case .cricket:
            return .cricket
        case .crossCountrySkiing:
            return .crossCountrySkiing
        case .crossTraining:
            return .crossTraining
        case .curling:
            return .curling
        case .cycling:
            return .cycling
        case .discSports:
            return .discSports
        case .downhillSkiing:
            return .downhillSkiing
        case .elliptical:
            return .elliptical
        case .equestrianSports:
            return .equestrianSports
        case .fencing:
            return .fencing
        case .fishing:
            return .fishing
        case .fitnessGaming:
            return .fitnessGaming
        case .flexibility:
            return .flexibility
        case .functionalStrengthTraining:
            return .functionalStrengthTraining
        case .golf:
            return .golf
        case .gymnastics:
            return .gymnastics
        case .handball:
            return .handball
        case .handCycling:
            return .handCycling
        case .hiit:
            return .highIntensityIntervalTraining
        case .hiking:
            return .hiking
        case .hockey:
            return .hockey
        case .hunting:
            return .hunting
        case .jumpRope:
            return .jumpRope
        case .kickboxing:
            return .kickboxing
        case .lacrosse:
            return .lacrosse
        case .martialArts:
            return .martialArts
        case .mindAndBody:
            return .mindAndBody
        case .mixedCardio:
            return .mixedCardio
        case .paddleSports:
            return .paddleSports
        case .pickleball:
            return .pickleball
        case .pilates:
            return .pilates
        case .play:
            return .play
        case .preparationAndRecovery:
            return .preparationAndRecovery
        case .racquetball:
            return .racquetball
        case .rowing:
            return .rowing
        case .rugby:
            return .rugby
        case .running:
            return .running
        case .sailing:
            return .sailing
        case .skatingSports:
            return .skatingSports
        case .snowboarding:
            return .snowboarding
        case .snowSports:
            return .snowSports
        case .soccer:
            return .soccer
        case .socialDance:
            return .socialDance
        case .softball:
            return .softball
        case .squash:
            return .squash
        case .stairClimbing:
            return .stairClimbing
        case .stairs:
            return .stairs
        case .stepTraining:
            return .stepTraining
        case .strengthTraining:
            return .traditionalStrengthTraining
        case .surfingSports:
            return .surfingSports
        case .swimBikeRun:
            return .swimBikeRun
        case .swimming:
            return .swimming
        case .tableTennis:
            return .tableTennis
        case .taiChi:
            return .taiChi
        case .tennis:
            return .tennis
        case .trackAndField:
            return .trackAndField
        case .transition:
            return .transition
        case .underwaterDiving:
            return .underwaterDiving
        case .volleyball:
            return .volleyball
        case .walking:
            return .walking
        case .waterFitness:
            return .waterFitness
        case .waterPolo:
            return .waterPolo
        case .waterSports:
            return .waterSports
        case .wheelchairRunPace:
            return .wheelchairRunPace
        case .wheelchairWalkPace:
            return .wheelchairWalkPace
        case .wrestling:
            return .wrestling
        case .yoga:
            return .yoga
        case .other:
            return .other
        }
    }

    private static let displayNames: [ExerciseType: String] = [
        .any: String(localized: "Any"),
        .americanFootball: String(localized: "American Football"),
        .archery: String(localized: "Archery"),
        .australianFootball: String(localized: "Australian Football"),
        .badminton: String(localized: "Badminton"),
        .barre: String(localized: "Barre"),
        .baseball: String(localized: "Baseball"),
        .basketball: String(localized: "Basketball"),
        .bowling: String(localized: "Bowling"),
        .boxing: String(localized: "Boxing"),
        .cardioDance: String(localized: "Cardio Dance"),
        .climbing: String(localized: "Climbing"),
        .cooldown: String(localized: "Cooldown"),
        .coreTraining: String(localized: "Core Training"),
        .cricket: String(localized: "Cricket"),
        .crossCountrySkiing: String(localized: "Cross Country Skiing"),
        .crossTraining: String(localized: "Cross Training"),
        .curling: String(localized: "Curling"),
        .cycling: String(localized: "Cycling"),
        .discSports: String(localized: "Disc Sports"),
        .downhillSkiing: String(localized: "Downhill Skiing"),
        .elliptical: String(localized: "Elliptical"),
        .equestrianSports: String(localized: "Equestrian"),
        .fencing: String(localized: "Fencing"),
        .fishing: String(localized: "Fishing"),
        .fitnessGaming: String(localized: "Fitness Gaming"),
        .flexibility: String(localized: "Flexibility"),
        .functionalStrengthTraining: String(localized: "Functional Strength"),
        .golf: String(localized: "Golf"),
        .gymnastics: String(localized: "Gymnastics"),
        .handball: String(localized: "Handball"),
        .handCycling: String(localized: "Hand Cycling"),
        .hiit: String(localized: "HIIT"),
        .hiking: String(localized: "Hiking"),
        .hockey: String(localized: "Hockey"),
        .hunting: String(localized: "Hunting"),
        .jumpRope: String(localized: "Jump Rope"),
        .kickboxing: String(localized: "Kickboxing"),
        .lacrosse: String(localized: "Lacrosse"),
        .martialArts: String(localized: "Martial Arts"),
        .mindAndBody: String(localized: "Mind and Body"),
        .mixedCardio: String(localized: "Mixed Cardio"),
        .paddleSports: String(localized: "Paddle Sports"),
        .pickleball: String(localized: "Pickleball"),
        .pilates: String(localized: "Pilates"),
        .play: String(localized: "Play"),
        .preparationAndRecovery: String(localized: "Preparation and Recovery"),
        .racquetball: String(localized: "Racquetball"),
        .rowing: String(localized: "Rowing"),
        .rugby: String(localized: "Rugby"),
        .running: String(localized: "Running"),
        .sailing: String(localized: "Sailing"),
        .skatingSports: String(localized: "Skating"),
        .snowboarding: String(localized: "Snowboarding"),
        .snowSports: String(localized: "Snow Sports"),
        .soccer: String(localized: "Soccer"),
        .socialDance: String(localized: "Social Dance"),
        .softball: String(localized: "Softball"),
        .squash: String(localized: "Squash"),
        .stairClimbing: String(localized: "Stair Climbing"),
        .stairs: String(localized: "Stairs"),
        .stepTraining: String(localized: "Step Training"),
        .strengthTraining: String(localized: "Strength"),
        .surfingSports: String(localized: "Surfing"),
        .swimBikeRun: String(localized: "Swim Bike Run"),
        .swimming: String(localized: "Swimming"),
        .tableTennis: String(localized: "Table Tennis"),
        .taiChi: String(localized: "Tai Chi"),
        .tennis: String(localized: "Tennis"),
        .trackAndField: String(localized: "Track and Field"),
        .transition: String(localized: "Transition"),
        .underwaterDiving: String(localized: "Underwater Diving"),
        .volleyball: String(localized: "Volleyball"),
        .walking: String(localized: "Walking"),
        .waterFitness: String(localized: "Water Fitness"),
        .waterPolo: String(localized: "Water Polo"),
        .waterSports: String(localized: "Water Sports"),
        .wheelchairRunPace: String(localized: "Wheelchair Run Pace"),
        .wheelchairWalkPace: String(localized: "Wheelchair Walk Pace"),
        .wrestling: String(localized: "Wrestling"),
        .yoga: String(localized: "Yoga"),
        .other: String(localized: "Other")
    ]
}

extension TimeBlockGoal {
    private nonisolated static let minutesInDay: Int = 24 * 60

    /// Returns the unlock time clamped to a valid day range.
    nonisolated var clampedUnlockMinutes: Int {
        min(max(unlockTimeMinutes, 0), Self.minutesInDay - 1)
    }

    /// Returns the unlock time as a Date on the given day.
    nonisolated func unlockDate(on date: Date = Date()) -> Date {
        let hour = clampedUnlockMinutes / 60
        let minute = clampedUnlockMinutes % 60
        return Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: date
        ) ?? date
    }

    /// Updates the unlock time using a Date value.
    nonisolated mutating func setUnlockTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        unlockTimeMinutes = min(max(minutes, 0), Self.minutesInDay - 1)
    }
}

