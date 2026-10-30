import Foundation
import Testing
@testable import PDFViewApp

@MainActor
private func makeStorageURL() throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("pdfview-tests")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("signature_profile.json")
}

@MainActor
private func realSignaturePNG() throws -> Data {
    let rendering = try #require(SignatureRenderer.renderText("Test User", fontName: "SnellRoundhand"))
    return rendering.pngData
}

@MainActor
@Test
func upsertAndReloadProfile() throws {
    let storageURL = try makeStorageURL()
    let store = SignatureStore(storageURL: storageURL)

    let profile = try SignatureProfile(
        fullName: "Test User",
        signaturePNGData: realSignaturePNG(),
        sourceKind: .type,
        typedText: "T. User",
        fontName: "SnellRoundhand"
    )

    try store.saveProfile(profile)
    #expect(store.profile?.fullName == "Test User")

    let reloadedStore = SignatureStore(storageURL: storageURL)
    let reloaded = try #require(reloadedStore.profile)
    #expect(reloaded.id == profile.id)
    #expect(reloaded.fullName == profile.fullName)
    #expect(reloaded.signaturePNGBase64 == profile.signaturePNGBase64)
    #expect(reloaded.sourceKind == profile.sourceKind)
    #expect(reloaded.typedText == "T. User")
    #expect(reloaded.fontName == "SnellRoundhand")
    // ISO8601 JSON encoding may drop sub-second precision in createdAt.
    let createdAtDelta = abs(reloaded.createdAt.timeIntervalSince1970 - profile.createdAt.timeIntervalSince1970)
    #expect(createdAtDelta < 1.0)
}

@MainActor
@Test
func deleteProfileClearsFileAndMemory() throws {
    let storageURL = try makeStorageURL()
    let store = SignatureStore(storageURL: storageURL)

    let profile = try SignatureProfile(
        fullName: "Delete User",
        signaturePNGData: realSignaturePNG(),
        sourceKind: .type
    )

    try store.saveProfile(profile)
    #expect(store.profile != nil)

    try store.deleteProfile()
    #expect(store.profile == nil)
    #expect(!FileManager.default.fileExists(atPath: storageURL.path))
}

@MainActor
@Test
func savingAnUndecodableImageIsRejected() throws {
    let storageURL = try makeStorageURL()
    let store = SignatureStore(storageURL: storageURL)
    // A PNG signature with no image data behind it.
    let profile = SignatureProfile(
        fullName: "Broken",
        signaturePNGData: Data([0x89, 0x50, 0x4E, 0x47]),
        sourceKind: .draw
    )

    #expect(throws: SignatureStore.SignatureError.self) {
        try store.saveProfile(profile)
    }
    #expect(store.profile == nil)
    #expect(!FileManager.default.fileExists(atPath: storageURL.path))
}

@MainActor
@Test
func loadingAnUndecodableImageIsIgnored() throws {
    let storageURL = try makeStorageURL()
    let profile = SignatureProfile(fullName: "Broken", signaturePNGData: Data("not a png".utf8), sourceKind: .draw)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(profile).write(to: storageURL)

    #expect(SignatureStore(storageURL: storageURL).profile == nil)
}

@MainActor
@Test
func profileSavedBeforeOptionalFieldsStillLoads() throws {
    let storageURL = try makeStorageURL()
    let base64 = try realSignaturePNG().base64EncodedString()
    let legacyJSON = """
    {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","fullName":"Legacy User",\
    "createdAt":"2026-01-02T03:04:05Z","signaturePNGBase64":"\(base64)","sourceKind":"draw"}
    """
    try Data(legacyJSON.utf8).write(to: storageURL)

    let profile = try #require(SignatureStore(storageURL: storageURL).profile)
    #expect(profile.fullName == "Legacy User")
    #expect(profile.sourceKind == .draw)
    #expect(profile.typedText == nil)
    #expect(profile.fontName == nil)
}
