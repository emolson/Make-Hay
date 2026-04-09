//
//  GoalStatusProvider.swift
//  Make Hay
//
//  Created by GitHub Copilot on 4/8/26.
//

/// Read-only provider exposing current gate state for reuse by other feature ViewModels.
protocol GoalStatusProvider: AnyObject {
    var isBlocking: Bool { get }
}