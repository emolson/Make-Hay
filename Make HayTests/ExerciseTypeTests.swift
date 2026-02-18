//
//  ExerciseTypeTests.swift
//  Make HayTests
//
//  Created by Ethan Olson on 2/17/26.
//

import Testing
@testable import Make_Hay
import HealthKit

struct ExerciseTypeTests {
    
    /// Validates that every ExerciseType case (except .any) maps to a non-nil HKWorkoutActivityType.
    @Test
    func everyExerciseTypeExceptAnyHasHKMapping() {
        for exerciseType in ExerciseType.allCases {
            if exerciseType == .any {
                #expect(exerciseType.hkWorkoutActivityType == nil)
            } else {
                #expect(
                    exerciseType.hkWorkoutActivityType != nil,
                    "ExerciseType.\(exerciseType.rawValue) should map to a non-nil HKWorkoutActivityType"
                )
            }
        }
    }
    
    /// Validates that allCases contains all enum cases exactly once.
    @Test
    func allCasesContainsAllCasesExactlyOnce() {
        let allCaseCount = ExerciseType.allCases.count
        let allCaseSet = Set(ExerciseType.allCases.map { $0.rawValue })
        
        #expect(
            allCaseCount == allCaseSet.count,
            "allCases has duplicates: \(allCaseCount) items but only \(allCaseSet.count) unique"
        )
    }
    
    /// Validates that every ExerciseType has a non-empty displayName.
    @Test
    func everyExerciseTypeHasDisplayName() {
        for exerciseType in ExerciseType.allCases {
            #expect(
                !exerciseType.displayName.isEmpty,
                "ExerciseType.\(exerciseType.rawValue) has empty displayName"
            )
        }
    }
    
    /// Validates that allCases matches the set of enum cases defined in ExerciseType.
    @Test
    func allCasesMatchesEnumDefinition() {
        // This test ensures that if a new case is added to ExerciseType,
        // it must be added to the allCases array to maintain consistency.
        let definedCases: Set<String> = [
            "any", "americanFootball", "archery", "australianFootball", "badminton",
            "baseball", "basketball", "bowling", "boxing", "climbing", "cricket",
            "crossTraining", "curling", "walking", "running", "cycling", "elliptical",
            "equestrianSports", "fencing", "fishing", "functionalStrengthTraining", "golf",
            "gymnastics", "handball", "hiking", "hockey", "hunting", "lacrosse",
            "martialArts", "mindAndBody", "paddleSports", "play", "preparationAndRecovery",
            "racquetball", "rowing", "rugby", "sailing", "skatingSports", "snowSports",
            "soccer", "softball", "squash", "stairClimbing", "surfingSports", "swimming",
            "tableTennis", "tennis", "trackAndField", "volleyball", "waterFitness", "waterPolo",
            "waterSports", "wrestling", "yoga", "barre", "coreTraining", "crossCountrySkiing",
            "downhillSkiing", "flexibility", "hiit", "jumpRope", "kickboxing", "pilates",
            "snowboarding", "stairs", "stepTraining", "wheelchairWalkPace", "wheelchairRunPace",
            "strengthTraining", "taiChi", "mixedCardio", "handCycling", "discSports",
            "fitnessGaming", "cardioDance", "socialDance", "pickleball", "cooldown",
            "swimBikeRun", "transition", "underwaterDiving", "other"
        ]
        
        let allCaseRawValues = Set(ExerciseType.allCases.map { $0.rawValue })
        
        #expect(
            allCaseRawValues == definedCases,
            "allCases does not match expected enum cases"
        )
    }
}
