# PDFView architecture

PDFView is a native macOS PDF reader with offline visual signing, built with Swift 6, SwiftUI, AppKit, and PDFKit. It targets macOS 14.2 and later.

This document describes the current source. Interactive behavior still requires the on-screen checks listed below.

## Document model and export

`PDFViewerDocument` owns the document's live PDFKit document and signature placements in PDF page coordinates. Export captures the live, unlocked document so edits to forms survive; the async path takes an independent PDFKit document copy before its first suspension and rebuilds navigation on that snapshot. Later form, annotation and page edits cannot mix states across exported pages. The viewing document lifecycle keeps opening and reading separate from the explicit Save Signed Copy action.

`SignedPDFExporter` renders page content and visual signature stamps into a flattened copy. It preserves media/crop boxes and rotation, restores link annotations and the outline by page index, and copies document attributes. Signature images fit within their placement bounds without changing aspect ratio. Export stages output on the destination volume, validates the result, then replaces the destination atomically. An image-rendering or write failure must not silently produce an incomplete copy.

Flattened stamps are page artwork. This is not certificate signing, identity verification, or tamper protection.

## PDFKit bridge and interaction

`PDFKitView` bridges PDFKit into SwiftUI. A `PDFPageOverlayViewProvider` draws signature overlays that follow each page during scrolling and zooming. Placement, selection, moving, and aspect-locked resizing use page coordinates; the document model remains the source of truth. Undo and redo operate on model changes.

Signing mode consumes placement clicks while normal reading retains PDFKit's selection and navigation behavior. Only signature widgets are treated as signature fields. `FormScan` uses `ReaderController.scanSignatureFields` to collect named signature fields and editable widgets in one cancellable page walk after the pages are shown; it reruns when a protected document is unlocked. Overlays redraw only when their inputs (placements, mode, stamp image, fields, selection) change.

Each page overlay exposes its stamps as `StampAccessibilityElement` buttons labelled by `StampAccessibility` (signer, page, field or on-screen position, with PDF-supplied field names flattened and truncated) and offering Remove and Move actions. Keyboard editing lives in `PDFKitView+Keyboard`: arrows move a selected stamp 1/10/50 pt, Option-Shift arrows resize it, and the PDF view claims arrow key equivalents before the Go menu while a stamp is selected. Escape follows `SigningFlowLogic.escapeAction` (export, signing, Find, selection); the Find field closes Find itself.

`PDFContentView` coordinates the toolbar, sidebar, signing setup, and document status. `SigningCommands` routes app menu commands to the focused document. Unsaved work is placements not in the last saved copy plus form values that differ from the last saved copy; the close guard reads it at decision time, and `AppDelegate` runs `TerminationReview` over every window's guard when the app quits. Saving reports success only after export finishes.

## Signature creation and storage

One app-wide `SignatureStore` is injected into document windows. It persists a signature and optional initials profile locally in the sandbox's Application Support directory and validates that stored image data decodes. `profile(for:)`, `saveProfile(_:for:)`, and `deleteProfile(for:)` operate on either `SignatureKind`; the existing `profile` property and default save/delete arguments still address the signature. Loading accepts the original bare-profile JSON; the next successful mutation writes both profiles atomically in one envelope. It does not upload or sync signatures.

`SignatureRenderer` handles drawn, typed, and imported artwork. Drawing uses a paper-white surface with black ink, smooth strokes, single-tap dots, uniform scaling, and crop-to-ink bounds. Typed signatures fit their names; imported images can remove white backgrounds. Editing restores existing artwork instead of discarding it.

`SignatureSetupSheet(existingProfile:kind:fullName:onCancel:onSave:)` supports both kinds, defaulting new initials to the first character of each name component. Its native drawing canvas becomes first responder and registers strokes and clearing with the sheet window's UndoManager; undo restores saved artwork when appropriate. Text fields retain native text undo. `SignatureRenderer.renderDate` returns transparent artwork with today's date, the current locale and time zone, and medium date style. Date, locale, time zone and font are injectable.

The Sign menu and compact toolbar menu select Signature, Initials, or Date. Missing initials open setup with kind `.initials` and resume the pending action after saving. `StampArtwork` snapshots the selected profile or renders the current date at placement time; each placement records kind, image bytes, signer and optional formatted date. All kinds share field/free placement, selection, move/resize, undo and export. VoiceOver labels name the stamp kind and signer or date.

## Reader features

The reader provides a page indicator, Go to Page, thumbnails and outline sidebar, Find, Print, remembered position, single/two-page layouts, and full screen. Zoom tracks fit and manual modes separately so view updates do not reset the user's zoom. Printing includes the visible signature placements through the export path.

`ReaderController` observes PDFKit page/scale and clip-view scroll changes, owns per-window sidebar/layout state and restores reading destinations after the view attaches or the PDF unlocks. `ReaderSidebar` binds a `PDFThumbnailView` to that same PDF view and renders a recursive outline. `ReaderCommands` uses the existing focused-scene action pattern for View, Go, Find and Print; standard SwiftUI window commands retain native full screen. Plain arrow and Page Up/Down events remain with PDFKit, except when a selected signature owns arrow-key editing.

`FindController` cancels prior searches and observes `PDFDocumentDidFindMatch` / `PDFDocumentDidEndFind` on the main queue. Generation checks discard queued stale callbacks; PDFKit selections remain on the main actor. `FindState` holds tested match counting and wrapping. The find bar requests text focus when opened; Escape in the Find field closes Find, and elsewhere finishes signing before closing Find. During export, Escape cancels the export first.

`ReadingPositionStore` is a Codable value with SHA-256 keys derived from standardized file paths. UserDefaults retains at most 200 entries in least-recently-used order. Values contain the page index, destination point and fit/manual zoom; paths and security bookmarks are not persisted. Invalid, corrupt or out-of-range positions are ignored.

`SignedCopyOperation` reserves the window's save slot before opening a save panel and prevents duplicate saves/printing while busy. It rejects the original by resolved path or file/volume resource identity, including symlinks and hard links. The exporter rechecks identity before committing. PDFKit rendering, serialization and validation stay on the main actor, with cancellation/yield boundaries between rendering, writing, geometry restoration and validation. Page boxes cross to a detached task as immutable `Sendable` values; the byte-level geometry repair uses no PDFKit objects. PDFKit serialization itself remains synchronous. Placements are captured at the start; later placement edits remain unexported. `PDFPrinting` checks source print permissions, prepares a temporary signed PDF when needed, retains it through the native print operation with auto-rotation, and removes it after completion, cancellation or error.

`DocumentProtection` owns an in-memory password for one open document and calls PDFKit's unlock API. `UnlockDocumentSheet` provides secure entry, wrong-password feedback and Cancel. The save accessory defaults to keeping protection when the password is known, exposes an explicit opt-out, and explains that an unknown password means an unprotected copy. Export writes both user and owner password options and validates the protected file by unlocking it before replacement. Encrypted output needing nonzero-origin geometry repair fails safely: appending plaintext streams would corrupt the encrypted file. The error advises making a normalized PDF using Print, reopening it and placing signatures again.

### Window integration

`DocumentProtectionSession` retains one `DocumentProtection` for the current PDF identity and discards it on replacement. A locked PDF opens `UnlockDocumentSheet`; Cancel leaves a banner naming unavailable actions and offering Unlock. Sign > Unlock… retries while locked. Both secure entry and PDFKit’s native unlock refresh protection/reader state and cancel/restart the field scan. Native entry cannot reveal its password, so the save accessory shows the unknown-password notice.

After reserving its export slot, `PDFContentView` calls `SignedCopyOperation.configure(_:originalURL:protection:)` before presenting the save panel. This supplies SwiftUI’s original URL even when PDFKit parsed bytes and has no `documentURL`, installs the protection accessory, and passes its choice into writing. Printing uses the same selected password for a temporary signed export, unlocks it in memory for AppKit, and removes the temporary file on completion, cancellation or failure.

`FormScan` collects widget references through the G1 scanner’s per-page callback instead of owning a second signature-field traversal. The coordinator cancels scans on unlock, replacement and dismantle, checks cancellation and document identity before publishing results, and keeps the editable form baseline scoped to that PDF.

`ReaderController` scopes bounds notifications to the PDF view's clip view and caches outline lookups, including missing entries, per page until document refresh.


## Privacy and file access

The app is sandboxed with user-selected read/write file access, printing permission and no network entitlement. User-selected import/export URLs use security-scoped access where needed. Signature profiles remain on this Mac. PDF data and signature images still require validation at their input boundaries; using Swift does not eliminate risks in document parsing.

## Packaging and distribution

`build_app.sh` builds with SwiftPM using stock macOS Bash 3.2, locates the executable through SwiftPM, and packages `PDFView.app`. It copies the Info.plist template, app icon, and sandbox entitlements, patches version metadata, and signs the executable and bundle. `ARCHES="arm64 x86_64"` produces a universal executable before signing.

`scripts/make-icon.swift` draws the icon procedurally with Core Graphics, exports the standard iconset resolutions, and invokes `iconutil`. The committed `Resources/AppIcon.icns` is the packaging input; regeneration requires only Swift and the macOS SDK.

Ad-hoc signing is the default. Optional Developer ID notarization submits a `ditto` ZIP, checks for Accepted, staples and validates the app, and rebuilds the ZIP with the ticket. Releases are built locally and currently distribute an ad-hoc signed app; the README documents the Gatekeeper override for each macOS version.

## Verification

Swift Testing covers document/export behavior, signature rendering/storage, reader logic, asynchronous find, position restoration, signed print preparation, export progress/cancellation and a 300-page main-actor responsiveness regression. Bundle checks cover Bash compatibility, resources, architectures, metadata, and signature integrity. `scripts/ci-local.sh` runs every check locally (there is no hosted CI); lint never rewrites the checkout.

On-screen verification remains necessary for menu routing, scrolling/zoom overlays, accessibility, multiwindow behavior, and first-launch Gatekeeper dialogs. Local builds and rendered bitmap checks do not establish that these UI flows or Apple's live notarization service succeeded.
