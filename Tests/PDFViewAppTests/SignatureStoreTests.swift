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

    try store.upsert(profile: profile)
    #expect(store.profile?.fullName == "Test User")

    let reloadedStore = SignatureStore(storageURL: storageURL)
    #expect(reloadedStore.profile == profile)
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

    try store.upsert(profile: profile)
    #expect(store.profile != nil)

    try store.deleteProfile()
    #expect(store.profile == nil)
    #expect(!FileManager.default.fileExists(atPath: storageURL.path))
}
