import Testing
import Foundation
@testable import PDFViewApp

@MainActor
@Test func upsertAndReloadProfile() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("pdfview-tests")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let storageURL = directory.appendingPathComponent("signature_profile.json")
    let store = SignatureStore(storageURL: storageURL)

    let profile = SignatureProfile(
        fullName: "Test User",
        signaturePNGData: Data([0x89, 0x50, 0x4E, 0x47]),
        sourceKind: .draw
    )

    try store.saveProfile(profile)
    #expect(store.profile?.fullName == "Test User")

    let reloadedStore = SignatureStore(storageURL: storageURL)
    let reloaded = try #require(reloadedStore.profile)
    #expect(reloaded.id == profile.id)
    #expect(reloaded.fullName == profile.fullName)
    #expect(reloaded.signaturePNGBase64 == profile.signaturePNGBase64)
    #expect(reloaded.sourceKind == profile.sourceKind)
    // ISO8601 JSON encoding may drop sub-second precision in createdAt.
    let createdAtDelta = abs(reloaded.createdAt.timeIntervalSince1970 - profile.createdAt.timeIntervalSince1970)
    #expect(createdAtDelta < 1.0)
}

@MainActor
@Test func deleteProfileClearsFileAndMemory() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("pdfview-tests")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let storageURL = directory.appendingPathComponent("signature_profile.json")
    let store = SignatureStore(storageURL: storageURL)

    let profile = SignatureProfile(
        fullName: "Delete User",
        signaturePNGData: Data([0x89, 0x50, 0x4E, 0x47]),
        sourceKind: .type
    )

    try store.saveProfile(profile)
    #expect(store.profile != nil)

    try store.deleteProfile()
    #expect(store.profile == nil)
    #expect(!FileManager.default.fileExists(atPath: storageURL.path))
}
