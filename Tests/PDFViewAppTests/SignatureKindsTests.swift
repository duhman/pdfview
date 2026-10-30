import Combine
import Foundation
import Testing
@testable import PDFViewApp

@MainActor
struct SignatureKindsTests {
    private func storageURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("signature_profile.json")
    }

    private func profile(_ text: String, source: SignatureProfile.SourceKind = .type) throws -> SignatureProfile {
        let image = try #require(SignatureRenderer.renderText(text, fontName: "SnellRoundhand"))
        return SignatureProfile(fullName: "Jane Appleseed", signaturePNGData: image.pngData, sourceKind: source)
    }

    @Test func legacyProfileMigratesWhenInitialsAreSaved() throws {
        let url = storageURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let signature = try profile("Jane Appleseed", source: .draw)
        let legacy = """
        {"id":"\(signature.id)","fullName":"Jane Appleseed","createdAt":"2026-01-02T03:04:05Z",\
        "signaturePNGBase64":"\(signature.signaturePNGBase64)","sourceKind":"draw"}
        """
        try Data(legacy.utf8).write(to: url)
        let store = SignatureStore(storageURL: url)
        #expect(store.profile(for: .signature)?.id == signature.id)
        #expect(store.profile(for: .initials) == nil)
        let initials = try profile("JA")
        try store.saveProfile(initials, for: .initials)
        let reloaded = SignatureStore(storageURL: url)
        #expect(reloaded.profile(for: .signature)?.signaturePNGData == signature.signaturePNGData)
        #expect(reloaded.profile(for: .initials)?.id == initials.id)
        #expect(reloaded.profile?.id == signature.id)
    }

    @Test(arguments: SignatureProfile.SourceKind.allCases)
    func profilesSaveAndDeleteIndependently(source: SignatureProfile.SourceKind) throws {
        let url = storageURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SignatureStore(storageURL: url)
        let signature = try profile("Jane", source: source)
        let initials = try profile("JA", source: source)
        try store.saveProfile(signature)
        try store.saveProfile(initials, for: .initials)
        try store.deleteProfile(for: .initials)
        #expect(SignatureStore(storageURL: url).profile(for: .signature)?.id == signature.id)
        #expect(SignatureStore(storageURL: url).profile(for: .initials) == nil)
        try store.saveProfile(initials, for: .initials)
        try store.deleteProfile()
        #expect(store.profile == nil)
        #expect(SignatureStore(storageURL: url).profile(for: .initials)?.id == initials.id)
        try store.deleteProfile(for: .initials)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func failedSavePreservesBothProfiles() throws {
        let url = storageURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SignatureStore(storageURL: url)
        let signature = try profile("Jane")
        let initials = try profile("JA")
        try store.saveProfile(signature)
        try store.saveProfile(initials, for: .initials)
        let invalid = SignatureProfile(fullName: "Jane", signaturePNGData: Data(), sourceKind: .import)
        #expect(throws: SignatureStore.SignatureError.self) { try store.saveProfile(invalid, for: .initials) }
        #expect(store.profile(for: .initials)?.id == initials.id)
        #expect(SignatureStore(storageURL: url).profile?.id == signature.id)
    }

    @Test func bothKindsPublishChanges() throws {
        let url = storageURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SignatureStore(storageURL: url)
        var changes = 0
        let subscription = store.objectWillChange.sink { changes += 1 }
        try store.saveProfile(profile("Jane"))
        try store.saveProfile(profile("JA"), for: .initials)
        try store.deleteProfile(for: .initials)
        #expect(changes == 3)
        withExtendedLifetime(subscription) {}
    }

    @Test func initialsDefaultUsesNameComponents() {
        #expect(SignatureKind.initials.defaultText(for: "  Jane   Appleseed \n") == "JA")
        #expect(SignatureKind.initials.defaultText(for: "åsa öberg") == "ÅÖ")
        #expect(SignatureKind.initials.defaultText(for: "李") == "李")
        #expect(SignatureKind.initials.defaultText(for: " \n").isEmpty)
        #expect(SignatureKind.signature.defaultText(for: "Jane Appleseed") == "Jane Appleseed")
    }
}
