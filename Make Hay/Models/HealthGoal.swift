//
//  HealthGoal.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import Foundation
import HealthKit

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
    
    // MARK: - Pending Changes
    
    /// Pending goal changes scheduled to take effect tomorrow at midnight.
    /// **Why separate type?** Avoids recursive value types while still persisting full state.
    var pendingGoal: PendingHealthGoal?
    
    /// The date when pending changes should take effect (midnight of next day).
    /// **Why Date?** Allows precise comparison to determine when to apply changes.
    var pendingGoalEffectiveDate: Date?
    
    /// Applies pending goal changes if the effective date has passed.
    /// **Why mutating?** This modifies the current goal state by copying pending values.
    /// - Returns: True if pending changes were applied, false if no changes were pending or not yet effective.
    @discardableResult
    mutating func applyPendingIfReady() -> Bool {
        guard let pendingGoal,
              let effectiveDate = pendingGoalEffectiveDate,
              Date() >= effectiveDate else {
            return false
        }
        
        // Apply all pending changes
        self.stepGoal = pendingGoal.stepGoal
        self.activeEnergyGoal = pendingGoal.activeEnergyGoal
        self.exerciseGoals = pendingGoal.exerciseGoals
        self.timeBlockGoal = pendingGoal.timeBlockGoal
        self.blockingStrategy = pendingGoal.blockingStrategy
        
        // Clear pending state
        self.pendingGoal = nil
        self.pendingGoalEffectiveDate = nil
        
        return true
    }
}

/// Snapshot of a goal change scheduled to apply later.
/// Stores the full goal configuration without recursive references.
struct PendingHealthGoal: Codable, Sendable, Equatable {
    var stepGoal: StepGoal
    var activeEnergyGoal: ActiveEnergyGoal
    var exerciseGoals: [ExerciseGoal]
    var timeBlockGoal: TimeBlockGoal
    var blockingStrategy: BlockingStrategy
    
    init(from goal: HealthGoal) {
        self.stepGoal = goal.stepGoal
        self.activeEnergyGoal = goal.activeEnergyGoal
        self.exerciseGoals = goal.exerciseGoals
        self.timeBlockGoal = goal.timeBlockGoal
        self.blockingStrategy = goal.blockingStrategy
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
    static func hasEnabledGoals(goal: HealthGoal) -> Bool {
        goal.stepGoal.isEnabled
            || goal.activeEnergyGoal.isEnabled
            || goal.exerciseGoals.contains(where: { $0.isEnabled })
            || goal.timeBlockGoal.isEnabled
    }

    /// Returns whether the configured goals are met for the provided snapshot.
    static func isGoalMet(goal: HealthGoal, snapshot: GoalEvaluationSnapshot) -> Bool {
        let progresses = goalProgresses(goal: goal, snapshot: snapshot)
        guard !progresses.isEmpty else { return true }
        return progresses.allSatisfy { $0 }
    }

    /// Returns whether apps should currently be blocked.
    static func shouldBlock(goal: HealthGoal, snapshot: GoalEvaluationSnapshot) -> Bool {
        let enabledGoals = goalProgresses(goal: goal, snapshot: snapshot)
        guard !enabledGoals.isEmpty else { return false }
        return !isGoalMet(goal: goal, snapshot: snapshot)
    }

    /// Returns whether easier edits should be deferred behind the pending-change flow.
    ///
    /// **Why separate from `shouldBlock`?** Deferral gate logic is intentionally
    /// decoupled from blocking logic so each can evolve independently. All enabled
    /// goals must be met before the user is permitted to weaken their commitments.
    static func shouldDeferChanges(goal: HealthGoal, snapshot: GoalEvaluationSnapshot) -> Bool {
        let progresses = goalProgresses(goal: goal, snapshot: snapshot)
        guard !progresses.isEmpty else { return false }
        // Strict: ALL enabled goals must be met before edits are allowed
        return !progresses.allSatisfy { $0 }
    }

    private static func goalProgresses(goal: HealthGoal, snapshot: GoalEvaluationSnapshot) -> [Bool] {
        var progresses: [Bool] = []

        if goal.stepGoal.isEnabled {
            progresses.append(snapshot.steps >= goal.stepGoal.target)
        }

        if goal.activeEnergyGoal.isEnabled {
            progresses.append(snapshot.activeEnergy >= Double(goal.activeEnergyGoal.target))
        }

        for exerciseGoal in goal.exerciseGoals where exerciseGoal.isEnabled {
            let current = snapshot.exerciseMinutesByGoalId[exerciseGoal.id] ?? 0
            progresses.append(current >= exerciseGoal.targetMinutes)
        }

        if goal.timeBlockGoal.isEnabled {
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
    static func shouldDeferEdits(
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

    private static func fetchExerciseMinutesByGoalId(
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

    private static func currentMinutesSinceMidnight(date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

/// Configuration for a steps goal.
struct StepGoal: Codable, Sendable, Equatable {
    var isEnabled: Bool = true
    var target: Int = 10_000
}

/// Configuration for an active energy (calories) goal.
struct ActiveEnergyGoal: Codable, Sendable, Equatable {
    var isEnabled: Bool = false
    var target: Int = 500
}

/// Configuration for an exercise minutes goal.
struct ExerciseGoal: Codable, Sendable, Equatable, Identifiable {
    var id: UUID = UUID()
    var isEnabled: Bool = true
    var targetMinutes: Int = 30
    var exerciseType: ExerciseType = .any
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
}

/// Defines when apps unlock relative to enabled goals.
///
/// **Why keep `.any`?** Retained for `Codable` backwards-compatibility with
/// persisted data. All runtime paths enforce `.all`; `.any` is never written.
enum BlockingStrategy: String, Codable, Sendable {
    case any
    case all
}

/// Supported exercise types for filtering workouts.
enum ExerciseType: String, Codable, CaseIterable, Sendable, Identifiable {
    case any
    case americanFootball
    case archery
    case australianFootball
    case badminton
    case baseball
    case basketball
    case bowling
    case boxing
    case climbing
    case cricket
    case crossTraining
    case curling
    case walking
    case running
    case cycling
    case elliptical
    case equestrianSports
    case fencing
    case fishing
    case functionalStrengthTraining
    case golf
    case gymnastics
    case handball
    case hiking
    case hockey
    case hunting
    case lacrosse
    case martialArts
    case mindAndBody
    case paddleSports
    case play
    case preparationAndRecovery
    case racquetball
    case rowing
    case rugby
    case sailing
    case skatingSports
    case snowSports
    case soccer
    case softball
    case squash
    case stairClimbing
    case surfingSports
    case swimming
    case tableTennis
    case tennis
    case trackAndField
    case volleyball
    case waterFitness
    case waterPolo
    case waterSports
    case wrestling
    case yoga
    case barre
    case coreTraining
    case crossCountrySkiing
    case downhillSkiing
    case flexibility
    case hiit
    case jumpRope
    case kickboxing
    case pilates
    case snowboarding
    case stairs
    case stepTraining
    case wheelchairWalkPace
    case wheelchairRunPace
    case strengthTraining
    case taiChi
    case mixedCardio
    case handCycling
    case discSports
    case fitnessGaming
    case cardioDance
    case socialDance
    case pickleball
    case cooldown
    case swimBikeRun
    case transition
    case underwaterDiving
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
        case .any:
            return "figure.mixed.cardio"
        case .americanFootball, .australianFootball, .rugby:
            return "football.fill"
        case .archery, .hunting:
            return "target"
        case .badminton, .handball, .lacrosse, .racquetball, .squash, .tableTennis, .tennis, .pickleball:
            return "tennis.racket"
        case .baseball, .softball:
            return "baseball.fill"
        case .basketball:
            return "basketball.fill"
        case .bowling:
            return "figure.bowling"
        case .boxing, .kickboxing, .martialArts, .wrestling:
            return "figure.mixed.cardio"
        case .climbing:
            return "figure.climbing"
        case .cricket:
            return "sportscourt.fill"
        case .crossTraining, .mixedCardio:
            return "figure.mixed.cardio"
        case .curling, .skatingSports, .snowSports, .crossCountrySkiing, .downhillSkiing, .snowboarding:
            return "snowflake"
        case .walking:
            return "figure.walk"
        case .running:
            return "figure.run"
        case .cycling:
            return "figure.outdoor.cycle"
        case .elliptical:
            return "figure.elliptical"
        case .equestrianSports:
            return "figure.mixed.cardio"
        case .fencing:
            return "sportscourt.fill"
        case .fishing:
            return "fish.fill"
        case .hiking:
            return "figure.hiking"
        case .golf:
            return "figure.golf"
        case .gymnastics:
            return "figure.mixed.cardio"
        case .hockey:
            return "hockey.puck.fill"
        case .mindAndBody, .yoga, .pilates, .taiChi, .flexibility:
            return "figure.yoga"
        case .paddleSports, .waterSports:
            return "figure.open.water.swim"
        case .play:
            return "figure.play"
        case .preparationAndRecovery, .cooldown:
            return "figure.cooldown"
        case .rowing:
            return "figure.rower"
        case .sailing:
            return "sailboat.fill"
        case .soccer:
            return "soccerball"
        case .stairClimbing, .stairs, .stepTraining:
            return "figure.stair.stepper"
        case .surfingSports:
            return "figure.surfing"
        case .swimming, .underwaterDiving:
            return "figure.pool.swim"
        case .trackAndField:
            return "figure.run"
        case .volleyball:
            return "volleyball.fill"
        case .waterFitness:
            return "drop.fill"
        case .waterPolo:
            return "water.waves"
        case .barre, .cardioDance, .socialDance:
            return "figure.dance"
        case .coreTraining:
            return "figure.core.training"
        case .hiit:
            return "figure.highintensity.intervaltraining"
        case .jumpRope:
            return "figure.jumprope"
        case .strengthTraining, .functionalStrengthTraining:
            return "dumbbell.fill"
        case .wheelchairWalkPace, .wheelchairRunPace:
            return "figure.roll"
        case .handCycling:
            return "figure.hand.cycling"
        case .discSports:
            return "sportscourt.fill"
        case .fitnessGaming:
            return "gamecontroller.fill"
        case .swimBikeRun, .transition:
            return "figure.mixed.cardio"
        case .other:
            return "figure.mixed.cardio"
        }
    }
    
    var hkWorkoutActivityType: HKWorkoutActivityType? {
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
        case .baseball:
            return .baseball
        case .basketball:
            return .basketball
        case .bowling:
            return .bowling
        case .boxing:
            return .boxing
        case .climbing:
            return .climbing
        case .cricket:
            return .cricket
        case .crossTraining:
            return .crossTraining
        case .curling:
            return .curling
        case .walking:
            return .walking
        case .running:
            return .running
        case .cycling:
            return .cycling
        case .elliptical:
            return .elliptical
        case .equestrianSports:
            return .equestrianSports
        case .fencing:
            return .fencing
        case .fishing:
            return .fishing
        case .functionalStrengthTraining:
            return .functionalStrengthTraining
        case .golf:
            return .golf
        case .gymnastics:
            return .gymnastics
        case .handball:
            return .handball
        case .hiking:
            return .hiking
        case .hockey:
            return .hockey
        case .hunting:
            return .hunting
        case .lacrosse:
            return .lacrosse
        case .martialArts:
            return .martialArts
        case .mindAndBody:
            return .mindAndBody
        case .paddleSports:
            return .paddleSports
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
        case .sailing:
            return .sailing
        case .skatingSports:
            return .skatingSports
        case .snowSports:
            return .snowSports
        case .soccer:
            return .soccer
        case .softball:
            return .softball
        case .squash:
            return .squash
        case .stairClimbing:
            return .stairClimbing
        case .surfingSports:
            return .surfingSports
        case .swimming:
            return .swimming
        case .tableTennis:
            return .tableTennis
        case .tennis:
            return .tennis
        case .trackAndField:
            return .trackAndField
        case .volleyball:
            return .volleyball
        case .waterFitness:
            return .waterFitness
        case .waterPolo:
            return .waterPolo
        case .waterSports:
            return .waterSports
        case .wrestling:
            return .wrestling
        case .yoga:
            return .yoga
        case .barre:
            return .barre
        case .coreTraining:
            return .coreTraining
        case .crossCountrySkiing:
            return .crossCountrySkiing
        case .downhillSkiing:
            return .downhillSkiing
        case .flexibility:
            return .flexibility
        case .hiit:
            return .highIntensityIntervalTraining
        case .jumpRope:
            return .jumpRope
        case .kickboxing:
            return .kickboxing
        case .pilates:
            return .pilates
        case .snowboarding:
            return .snowboarding
        case .stairs:
            return .stairs
        case .stepTraining:
            return .stepTraining
        case .wheelchairWalkPace:
            return .wheelchairWalkPace
        case .wheelchairRunPace:
            return .wheelchairRunPace
        case .strengthTraining:
            return .traditionalStrengthTraining
        case .taiChi:
            return .taiChi
        case .mixedCardio:
            return .mixedCardio
        case .handCycling:
            return .handCycling
        case .discSports:
            return .discSports
        case .fitnessGaming:
            return .fitnessGaming
        case .cardioDance:
            return .cardioDance
        case .socialDance:
            return .socialDance
        case .pickleball:
            return .pickleball
        case .cooldown:
            return .cooldown
        case .swimBikeRun:
            return .swimBikeRun
        case .transition:
            return .transition
        case .underwaterDiving:
            return .underwaterDiving
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
        .baseball: String(localized: "Baseball"),
        .basketball: String(localized: "Basketball"),
        .bowling: String(localized: "Bowling"),
        .boxing: String(localized: "Boxing"),
        .climbing: String(localized: "Climbing"),
        .cricket: String(localized: "Cricket"),
        .crossTraining: String(localized: "Cross Training"),
        .curling: String(localized: "Curling"),
        .walking: String(localized: "Walking"),
        .running: String(localized: "Running"),
        .cycling: String(localized: "Cycling"),
        .elliptical: String(localized: "Elliptical"),
        .equestrianSports: String(localized: "Equestrian"),
        .fencing: String(localized: "Fencing"),
        .fishing: String(localized: "Fishing"),
        .functionalStrengthTraining: String(localized: "Functional Strength"),
        .golf: String(localized: "Golf"),
        .gymnastics: String(localized: "Gymnastics"),
        .handball: String(localized: "Handball"),
        .hiking: String(localized: "Hiking"),
        .hockey: String(localized: "Hockey"),
        .hunting: String(localized: "Hunting"),
        .lacrosse: String(localized: "Lacrosse"),
        .martialArts: String(localized: "Martial Arts"),
        .mindAndBody: String(localized: "Mind and Body"),
        .paddleSports: String(localized: "Paddle Sports"),
        .play: String(localized: "Play"),
        .preparationAndRecovery: String(localized: "Preparation and Recovery"),
        .racquetball: String(localized: "Racquetball"),
        .rowing: String(localized: "Rowing"),
        .rugby: String(localized: "Rugby"),
        .sailing: String(localized: "Sailing"),
        .skatingSports: String(localized: "Skating"),
        .snowSports: String(localized: "Snow Sports"),
        .soccer: String(localized: "Soccer"),
        .softball: String(localized: "Softball"),
        .squash: String(localized: "Squash"),
        .stairClimbing: String(localized: "Stair Climbing"),
        .surfingSports: String(localized: "Surfing"),
        .swimming: String(localized: "Swimming"),
        .tableTennis: String(localized: "Table Tennis"),
        .tennis: String(localized: "Tennis"),
        .trackAndField: String(localized: "Track and Field"),
        .volleyball: String(localized: "Volleyball"),
        .waterFitness: String(localized: "Water Fitness"),
        .waterPolo: String(localized: "Water Polo"),
        .waterSports: String(localized: "Water Sports"),
        .wrestling: String(localized: "Wrestling"),
        .yoga: String(localized: "Yoga"),
        .barre: String(localized: "Barre"),
        .coreTraining: String(localized: "Core Training"),
        .crossCountrySkiing: String(localized: "Cross Country Skiing"),
        .downhillSkiing: String(localized: "Downhill Skiing"),
        .flexibility: String(localized: "Flexibility"),
        .hiit: String(localized: "HIIT"),
        .jumpRope: String(localized: "Jump Rope"),
        .kickboxing: String(localized: "Kickboxing"),
        .pilates: String(localized: "Pilates"),
        .snowboarding: String(localized: "Snowboarding"),
        .stairs: String(localized: "Stairs"),
        .stepTraining: String(localized: "Step Training"),
        .wheelchairWalkPace: String(localized: "Wheelchair Walk Pace"),
        .wheelchairRunPace: String(localized: "Wheelchair Run Pace"),
        .strengthTraining: String(localized: "Strength"),
        .taiChi: String(localized: "Tai Chi"),
        .mixedCardio: String(localized: "Mixed Cardio"),
        .handCycling: String(localized: "Hand Cycling"),
        .discSports: String(localized: "Disc Sports"),
        .fitnessGaming: String(localized: "Fitness Gaming"),
        .cardioDance: String(localized: "Cardio Dance"),
        .socialDance: String(localized: "Social Dance"),
        .pickleball: String(localized: "Pickleball"),
        .cooldown: String(localized: "Cooldown"),
        .swimBikeRun: String(localized: "Swim Bike Run"),
        .transition: String(localized: "Transition"),
        .underwaterDiving: String(localized: "Underwater Diving"),
        .other: String(localized: "Other")
    ]
}

extension TimeBlockGoal {
    private static let minutesInDay: Int = 24 * 60

    /// Returns the unlock time clamped to a valid day range.
    var clampedUnlockMinutes: Int {
        min(max(unlockTimeMinutes, 0), Self.minutesInDay - 1)
    }

    /// Returns the unlock time as a Date on the given day.
    func unlockDate(on date: Date = Date()) -> Date {
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
    mutating func setUnlockTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        unlockTimeMinutes = min(max(minutes, 0), Self.minutesInDay - 1)
    }
}

extension HealthGoal {
    static let storageKey: String = "healthGoalData"
    static let legacyStepKey: String = "dailyStepGoal"
    
    static func load(from defaults: UserDefaults = SharedStorage.appGroupDefaults) -> HealthGoal {
        if let dataString = defaults.string(forKey: storageKey),
           let data = dataString.data(using: .utf8),
           let goal = try? JSONDecoder().decode(HealthGoal.self, from: data) {
            return goal
        }
        
        let legacyStepGoal = defaults.integer(forKey: legacyStepKey)
        if legacyStepGoal > 0 {
            var migrated = HealthGoal()
            migrated.stepGoal.target = legacyStepGoal
            save(migrated, to: defaults)
            return migrated
        }
        
        return HealthGoal()
    }
    
    static func save(_ goal: HealthGoal, to defaults: UserDefaults = SharedStorage.appGroupDefaults) {
        if let encoded = encode(goal) {
            defaults.set(encoded, forKey: storageKey)
        }
    }
    
    static func encode(_ goal: HealthGoal) -> String? {
        guard let data = try? JSONEncoder().encode(goal) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    static func decode(from string: String) -> HealthGoal? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(HealthGoal.self, from: data)
    }
}
