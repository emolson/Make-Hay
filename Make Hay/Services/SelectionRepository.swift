//
//  SelectionRepository.swift
//  Make Hay
//
//  Created by GitHub Copilot on 4/9/26.
//

import FamilyControls
import Foundation
import os.log

/// File-backed repository for `FamilyActivitySelection` payloads.
///
/// **Why this type?** Centralises all plist read/write logic that was previously
/// scattered across `BlockerService`'s private static methods. A single write path
/// enforces atomic writes with `FileProtectionType.completeUntilFirstUserAuthentication`,
/// and every load path quarantines corrupt files instead of silently returning empty data.
///
/// **Sendable:** All stored properties are immutable value types or `Sendable`
/// singletons (`FileManager.default`), so the struct is safe to share across actors.
struct SelectionRepository: SelectionRepositoryProtocol, Sendable {

    // MARK: - Configuration

    private let selectionURL: URL
    private let pendingSelectionURL: URL
    private let pendingSelectionDateURL: URL

    /// File protection level applied after every write.
    ///
    /// `completeUntilFirstUserAuthentication` keeps the payload encrypted at rest
    /// until the device is unlocked after boot, while still readable by the
    /// DeviceActivity extension during background execution.
    private static let fileProtection: FileProtectionType = .completeUntilFirstUserAuthentication

    private static let logger = AppLogger.logger(category: "SelectionRepository")

    // MARK: - Initialization

    /// Creates a repository backed by the App Group container.
    ///
    /// Falls back to the Documents directory when the App Group container is
    /// unavailable (e.g., misconfigured entitlements on the Simulator).
    init() {
        let base = SharedStorage.appGroupContainerURL ?? Self.fallbackDocumentsURL()
        self.selectionURL = base.appendingPathComponent("FamilyActivitySelection.plist")
        self.pendingSelectionURL = base.appendingPathComponent("PendingFamilyActivitySelection.plist")
        self.pendingSelectionDateURL = base.appendingPathComponent("PendingFamilyActivitySelectionDate.plist")
    }

    /// Testable initializer accepting explicit URLs.
    init(
        selectionURL: URL,
        pendingSelectionURL: URL,
        pendingSelectionDateURL: URL
    ) {
        self.selectionURL = selectionURL
        self.pendingSelectionURL = pendingSelectionURL
        self.pendingSelectionDateURL = pendingSelectionDateURL
    }

    // MARK: - SelectionRepositoryProtocol

    func loadSelection() -> FamilyActivitySelection {
        load(FamilyActivitySelection.self, from: selectionURL) ?? FamilyActivitySelection()
    }

    func saveSelection(_ selection: FamilyActivitySelection) throws {
        try writeProtected(selection, to: selectionURL)
    }

    func loadPendingSelection() -> FamilyActivitySelection? {
        load(FamilyActivitySelection.self, from: pendingSelectionURL)
    }

    func loadPendingSelectionDate() -> Date? {
        load(Date.self, from: pendingSelectionDateURL)
    }

    func savePendingSelection(_ selection: FamilyActivitySelection, effectiveDate: Date) throws {
        try writeProtected(selection, to: pendingSelectionURL)
        try writeProtected(effectiveDate, to: pendingSelectionDateURL)
    }

    func clearPendingSelection() {
        let fm = FileManager.default
        for url in [pendingSelectionURL, pendingSelectionDateURL] where fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - Private Helpers

    /// Decodes a `Codable` value from a PropertyList file.
    ///
    /// When the file exists but cannot be decoded (corrupt payload, schema change),
    /// the bad file is quarantined with a `.corrupt` suffix and `nil` is returned.
    /// This explicit migration handling surfaces the event in logs rather than
    /// silently swallowing it.
    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try PropertyListDecoder().decode(type, from: data)
        } catch {
            Self.logger.error("Corrupt payload detected — quarantining file.")
            quarantine(url)
            return nil
        }
    }

    /// Encodes a `Codable` value and writes it atomically with file protection.
    private func writeProtected<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.protectionKey: Self.fileProtection],
            ofItemAtPath: url.path
        )
    }

    /// Moves a corrupt file to a `.corrupt` suffix so it can be inspected later
    /// without blocking normal operation.
    private func quarantine(_ url: URL) {
        let quarantineURL = url.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: quarantineURL)
        try? FileManager.default.moveItem(at: url, to: quarantineURL)
    }

    private static func fallbackDocumentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }
}
