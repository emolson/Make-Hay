//
//  FamilyActivitySelection+Sendable.swift
//  Make Hay
//
//  Created by GitHub Copilot on 4/12/26.
//

import FamilyControls

/// `FamilyActivitySelection` is used in Make Hay as an immutable value snapshot.
/// `FamilyControls` does not currently annotate it as `Sendable`, so strict Swift 6
/// concurrency requires an explicit local conformance when selections cross actor
/// boundaries between UI view models and the blocker service.
extension FamilyActivitySelection: @unchecked @retroactive Sendable {}