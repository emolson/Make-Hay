//
//  HealthGoalExpirationTests.swift
//  Make HayTests
//
//  Tests that one-time ("today only") goals expire correctly and that
//  recurring goals with no expirationDate are unaffected.
//

import Foundation
import Testing
@testable import Make_Hay

struct HealthGoalExpirationTests {

    // MARK: - includestoday

    @Test("todayOnly schedule includes today")
    func todayOnlyIncludesToday() {
        let schedule: GoalSchedule = .todayOnly(expires: .distantFuture)
        #expect(schedule.includestoday,
                "A todayOnly schedule should always include today")
    }

    @Test("Recurring schedule without today excludes today")
    func scheduleWithoutTodayExcludesToday() {
        // Build a schedule that contains every day EXCEPT today
        var days = Set(Weekday.allCases)
        days.remove(Weekday.today)
        let schedule: GoalSchedule = .recurring(days)
        #expect(!schedule.includestoday)
    }

    @Test("displaySummary for todayOnly shows Today only")
    func todayOnlyDisplaySummary() {
        let schedule: GoalSchedule = .todayOnly(expires: .distantFuture)
        #expect(schedule.displaySummary == String(localized: "Today only"))
    }

    // MARK: - expireGoalsIfNeeded

    @Test("One-time step goal is disabled after expiration")
    func expiredStepGoalIsDisabled() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        var goal = HealthGoal(
            stepGoal: StepGoal(isEnabled: true, target: 5_000, schedule: .todayOnly(expires: yesterday))
        )

        let changed = goal.expireGoalsIfNeeded()

        #expect(changed)
        #expect(!goal.stepGoal.isEnabled, "Step goal should be disabled after expiration")
        #expect(goal.stepGoal.schedule == .everyDay, "Schedule should reset to everyDay after expiration")
    }

    @Test("One-time active energy goal is disabled after expiration")
    func expiredActiveEnergyGoalIsDisabled() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        var goal = HealthGoal(
            activeEnergyGoal: ActiveEnergyGoal(isEnabled: true, target: 300, schedule: .todayOnly(expires: yesterday))
        )

        let changed = goal.expireGoalsIfNeeded()

        #expect(changed)
        #expect(!goal.activeEnergyGoal.isEnabled)
        #expect(goal.activeEnergyGoal.schedule == .everyDay)
    }

    @Test("One-time exercise goal is disabled after expiration")
    func expiredExerciseGoalIsDisabled() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        var goal = HealthGoal(
            exerciseGoals: [
                ExerciseGoal(isEnabled: true, targetMinutes: 30, schedule: .todayOnly(expires: yesterday))
            ]
        )

        let changed = goal.expireGoalsIfNeeded()

        #expect(changed)
        #expect(!goal.exerciseGoals[0].isEnabled)
        #expect(goal.exerciseGoals[0].schedule == .everyDay)
    }

    @Test("One-time time block goal is disabled after expiration")
    func expiredTimeBlockGoalIsDisabled() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        var goal = HealthGoal(
            timeBlockGoal: TimeBlockGoal(isEnabled: true, unlockTimeMinutes: 19 * 60, schedule: .todayOnly(expires: yesterday))
        )

        let changed = goal.expireGoalsIfNeeded()

        #expect(changed)
        #expect(!goal.timeBlockGoal.isEnabled)
        #expect(goal.timeBlockGoal.schedule == .everyDay)
    }

    @Test("Recurring goal is not expired")
    func recurringGoalNotExpired() {
        var goal = HealthGoal(
            stepGoal: StepGoal(isEnabled: true, target: 10_000, schedule: .everyDay)
        )

        let changed = goal.expireGoalsIfNeeded()

        #expect(!changed, "Recurring goals should not be expired")
        #expect(goal.stepGoal.isEnabled)
    }

    @Test("Goal with future expirationDate is not expired")
    func futureExpirationNotExpired() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        var goal = HealthGoal(
            stepGoal: StepGoal(isEnabled: true, target: 5_000, schedule: .todayOnly(expires: tomorrow))
        )

        let changed = goal.expireGoalsIfNeeded()

        #expect(!changed, "Goal should not expire before its expirationDate")
        #expect(goal.stepGoal.isEnabled)
        #expect(goal.stepGoal.schedule.expirationDate != nil)
    }

    @Test("Multiple goals expire independently")
    func multipleGoalsExpireIndependently() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        var goal = HealthGoal(
            stepGoal: StepGoal(isEnabled: true, target: 5_000, schedule: .todayOnly(expires: yesterday)),
            activeEnergyGoal: ActiveEnergyGoal(isEnabled: true, target: 300, schedule: .todayOnly(expires: tomorrow))
        )

        let changed = goal.expireGoalsIfNeeded()

        #expect(changed)
        #expect(!goal.stepGoal.isEnabled, "Expired step goal should be disabled")
        #expect(goal.activeEnergyGoal.isEnabled, "Non-expired energy goal should remain enabled")
    }

    // MARK: - Codable round-trip

    @Test("GoalSchedule survives encode/decode round-trip")
    func goalScheduleRoundTrip() throws {
        let tomorrow = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        )
        let original = HealthGoal(
            stepGoal: StepGoal(isEnabled: true, target: 5_000, schedule: .todayOnly(expires: tomorrow))
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HealthGoal.self, from: data)

        #expect(decoded.stepGoal.schedule.expirationDate == tomorrow)
        if case .todayOnly = decoded.stepGoal.schedule {
            // Expected
        } else {
            Issue.record("Expected .todayOnly schedule after round-trip")
        }
    }

}
