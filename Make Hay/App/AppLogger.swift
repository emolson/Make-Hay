//
//  AppLogger.swift
//  Make Hay
//
//  Created by GitHub Copilot on 4/9/26.
//

import os.log

/// Centralized logger factory for privacy-safe diagnostics.
///
/// **Why centralize?** Every file previously created its own `Logger(subsystem:category:)`
/// with a hardcoded subsystem string. This factory eliminates that duplication and
/// establishes a single, documented convention: log call sites use only **static,
/// coarse event descriptions** — never interpolated system errors, file paths, HealthKit
/// type identifiers, or health-derived values. Raw `Error` instances must be mapped to
/// a domain-specific code (e.g., `EvaluationFailureReason`) before being persisted or
/// logged, keeping OS-provided diagnostics out of unified logging output.
///
/// If you need a new category, call `AppLogger.logger(category:)` once in a `static let`
/// and use it throughout the file.
enum AppLogger {
    /// Bundle-identifier-based subsystem shared by all loggers in the main app.
    nonisolated static let subsystem = "com.ethanolson.Make-Hay"

    /// Creates a `Logger` scoped to the given category.
    ///
    /// - Parameter category: A short, stable label for the subsystem area
    ///   (e.g., `"BackgroundHealthMonitor"`, `"BlockerService"`).
    /// - Returns: A configured `Logger` ready for use.
    nonisolated static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    /// Emits a privacy-safe debug trace to unified logging and, in debug builds,
    /// mirrors it to stdout for fast Xcode console debugging.
    nonisolated static func trace(category: String, message: String) {
        logger(category: category).debug("\(message, privacy: .public)")
#if DEBUG
        print("[\(category)] \(message)")
#endif
    }
}
