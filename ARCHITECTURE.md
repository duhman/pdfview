# PDFView architecture

PDFView is a native macOS PDF reader with offline visual signing, built with Swift 6, SwiftUI, AppKit, and PDFKit. It targets macOS 14.2 and later.

This document describes the current source. Interactive behavior still requires the on-screen checks listed below.

## Document model and export

`PDFViewerDocument` owns the document's live PDFKit document and signature placements in PDF page coordinates. The live, unlocked document is the export source so edits to forms survive. The viewing document lifecycle keeps opening and reading separate from the explicit Save Signed Copy action.

`SignedPDFExporter` renders page content and visual signature stamps into a flattened copy. It preserves media/crop boxes and rotation, restores link annotations and the outline by page index, and copies document attributes. Signature images fit within their placement bounds without changing aspect ratio. Export stages output on the destination volume, validates the result, then replaces the destination atomically. An image-rendering or write failure must not silently produce an incomplete copy.

Flattened stamps are page artwork. This is not certificate signing, identity verification, or tamper protection.

## PDFKit bridge and interaction

`PDFKitView` bridges PDFKit into SwiftUI. A `PDFPageOverlayViewProvider` draws signature overlays that follow each page during scrolling and zooming. Placement, selection, moving, and aspect-locked resizing use page coordinates; the document model remains the source of truth. Undo and redo operate on model changes.

Signing mode consumes placement clicks while normal reading retains PDFKit's selection and navigation behavior. Only signature widgets are treated as signature fields; detection refreshes when a protected document is unlocked. Keyboard placement, focus, and accessibility announcements accompany pointer interaction.

`PDFContentView` coordinates the toolbar, sidebar, signing setup, and document status. `SigningCommands` routes app menu commands to the focused document. Unsaved placements require a close confirmation; saving reports success only after export finishes.

## Signature creation and storage

One app-wide `SignatureStore` is injected into document windows. It persists a signature and optional initials profile locally in the sandbox's Application Support directory and validates that stored image data decodes. `profile(for:)`, `saveProfile(_:for:)`, and `deleteProfile(for:)` operate on either `SignatureKind`; the existing `profile` property and default save/delete arguments still address the signature. Loading accepts the original bare-profile JSON; the next successful mutation writes both profiles atomically in one envelope. It does not upload or sync signatures.

`SignatureRenderer` handles drawn, typed, and imported artwork. Drawing uses a paper-white surface with black ink, smooth strokes, single-tap dots, uniform scaling, and crop-to-ink bounds. Typed signatures fit their names; imported images can remove white backgrounds. Editing restores existing artwork instead of discarding it.

`SignatureSetupSheet(existingProfile:kind:fullName:onCancel:onSave:)` supports both kinds, defaulting new initials to the first character of each name component. Its native drawing canvas becomes first responder and registers strokes and clearing with the sheet window's UndoManager; undo restores saved artwork when appropriate. Text fields retain native text undo. `SignatureRenderer.renderDate` returns the same transparent PNG/point-size rendering as typed signatures, using today's date, the current locale and time zone, medium date style, or an optional custom format. Date, locale, time zone and font are injectable. The integrator must expose initials setup and wire initials/date menus and placement; this slice leaves document coordination unchanged.

## Reader features

The reader provides a page indicator, Go to Page, thumbnails and outline sidebar, Find, Print, remembered position, single/two-page layouts, and full screen. Zoom tracks fit and manual modes separately so view updates do not reset the user's zoom. Printing includes the visible signature placements through the export path.

`ReaderController` observes PDFKit page/scale and clip-view scroll changes, owns per-window sidebar/layout state and restores reading destinations after the view attaches or the PDF unlocks. `ReaderSidebar` binds a `PDFThumbnailView` to that same PDF view and renders a recursive outline. `ReaderCommands` uses the existing focused-scene action pattern for View, Go, Find and Print; standard SwiftUI window commands retain native full screen. Plain arrow and Page Up/Down events remain with PDFKit, except when a selected signature owns arrow-key editing.

`FindController` cancels prior searches and observes `PDFDocumentDidFindMatch` / `PDFDocumentDidEndFind` on the main queue. Generation checks discard queued stale callbacks; PDFKit selections remain on the main actor. `FindState` holds tested match counting and wrapping. The find bar requests text focus when opened; Escape finishes signing before closing Find. During export, Escape cancels the export first.

`ReadingPositionStore` is a Codable value with SHA-256 keys derived from standardized file paths. UserDefaults retains at most 200 entries in least-recently-used order. Values contain the page index, destination point and fit/manual zoom; paths and security bookmarks are not persisted. Invalid, corrupt or out-of-range positions are ignored.

`SignedCopyOperation` reserves the window's save slot before opening a save panel and prevents duplicate saves/printing while busy. The async exporter renders on the main actor, yields after each page, reports determinate progress and checks cancellation before atomic replacement. PDFKit objects never move to a worker thread. Final PDFKit serialization and validation are synchronous stages, so cancellation takes effect at the surrounding boundaries. Placements are captured at the start; later placement edits remain unexported. `PDFPrinting` checks source print permissions, prepares a temporary signed PDF when needed, retains it through the native print operation with auto-rotation, and removes it after completion, cancellation or error.

## Privacy and file access

The app is sandboxed with user-selected read/write file access, printing permission and no network entitlement. User-selected import/export URLs use security-scoped access where needed. Signature profiles remain on this Mac. PDF data and signature images still require validation at their input boundaries; using Swift does not eliminate risks in document parsing.

## Packaging and distribution

`build_app.sh` builds with SwiftPM using stock macOS Bash 3.2, locates the executable through SwiftPM, and packages `PDFView.app`. It copies the Info.plist template, app icon, and sandbox entitlements, patches version metadata, and signs the executable and bundle. `ARCHES="arm64 x86_64"` produces a universal executable before signing.

`scripts/make-icon.swift` draws the icon procedurally with Core Graphics, exports the standard iconset resolutions, and invokes `iconutil`. The committed `Resources/AppIcon.icns` is the packaging input; regeneration requires only Swift and the macOS SDK.

Ad-hoc signing is the default. Optional Developer ID notarization submits a `ditto` ZIP, checks for Accepted, staples and validates the app, and rebuilds the ZIP with the ticket. Releases are built locally and currently distribute an ad-hoc signed app; the README documents the Gatekeeper override for each macOS version.

## Verification

Swift Testing covers document/export behavior, signature rendering/storage, reader logic, asynchronous find, position restoration, signed print preparation, export progress/cancellation and a 300-page main-actor responsiveness regression. Bundle checks cover Bash compatibility, resources, architectures, metadata, and signature integrity. `scripts/ci-local.sh` runs every check locally (there is no hosted CI); lint never rewrites the checkout.

On-screen verification remains necessary for menu routing, scrolling/zoom overlays, accessibility, multiwindow behavior, and first-launch Gatekeeper dialogs. Local builds and rendered bitmap checks do not establish that these UI flows or Apple's live notarization service succeeded.
