//
//  KeyValueStorage.swift
//  Make Hay
//
//  Created by GitHub Copilot on 2/28/26.
//

import Foundation

/// Lightweight abstraction over key-value persistence (e.g. `UserDefaults`).
///
/// **Why this protocol?** `HealthService` needs to persist a single flag
/// (`hasRequestedHealthAuthorization`) across launches. Coupling directly to
/// `UserDefaults.standard` makes unit tests hit real disk defaults, introducing
/// flakiness and cross-test pollution. Injecting a protocol lets tests supply an
/// in-memory stub instead.
protocol KeyValueStorage: Sendable {
    /// Returns the Boolean value associated with the specified key.
    func bool(forKey key: String) -> Bool
    /// Sets the value of the specified key to the specified Boolean value.
    func set(_ value: Bool, forKey key: String)
}

// MARK: - UserDefaults Conformance

/// `UserDefaults` already satisfies the contract — just declare conformance.
///
/// **Why `@unchecked Sendable`?** `UserDefaults` is thread-safe per Apple docs,
/// but the compiler can't verify that automatically. `@unchecked` acknowledges
/// the invariant without silencing real concurrency issues elsewhere.
extension UserDefaults: KeyValueStorage, @unchecked @retroactive Sendable {}
