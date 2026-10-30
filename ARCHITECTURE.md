# PDFView architecture

PDFView is a native macOS PDF reader with offline visual signing, built with Swift 6, SwiftUI, AppKit, and PDFKit. It targets macOS 14.2 and later.

This document describes the **target architecture for the release in progress**. The export, signature creation, and reader interaction changes are being integrated separately; names and responsibilities below are targets until those changes land.

## Document model and export — in progress

`PDFViewerDocument` owns the document's live PDFKit document and signature placements in PDF page coordinates. The live, unlocked document is the export source so edits to forms survive. The viewing document lifecycle keeps opening and reading separate from the explicit Save Signed Copy action.

`SignedPDFExporter` renders page content and visual signature stamps into a flattened copy. It preserves media/crop boxes and rotation, restores link annotations and the outline by page index, and copies document attributes. Signature images fit within their placement bounds without changing aspect ratio. Export writes to a temporary sibling, validates the result, then replaces the destination atomically. An image-rendering or write failure must not silently produce an incomplete copy.

Flattened stamps are page artwork. This is not certificate signing, identity verification, or tamper protection.

## PDFKit bridge and interaction — in progress

`PDFKitView` bridges PDFKit into SwiftUI. A `PDFPageOverlayViewProvider` draws signature overlays that follow each page during scrolling and zooming. Placement, selection, moving, and aspect-locked resizing use page coordinates; the document model remains the source of truth. Undo and redo operate on model changes.

Signing mode consumes placement clicks while normal reading retains PDFKit's selection and navigation behavior. Only signature widgets are treated as signature fields; detection refreshes when a protected document is unlocked. Keyboard placement, focus, and accessibility announcements accompany pointer interaction.

`PDFContentView` coordinates the toolbar, sidebar, signing setup, and document status. `SigningCommands` routes app menu commands to the focused document. Unsaved placements require a close confirmation; saving reports success only after export finishes.

## Signature creation and storage — in progress

One app-wide `SignatureStore` is injected into document windows. It persists a signature profile locally in the sandbox's Application Support directory and validates that stored image data decodes. It does not upload or sync signatures.

`SignatureRenderer` handles drawn, typed, and imported artwork. Drawing uses a paper-white surface with black ink, smooth strokes, single-tap dots, uniform scaling, and crop-to-ink bounds. Typed signatures fit their names; imported images can remove white backgrounds. Editing restores existing artwork instead of discarding it.

## Reader features — in progress

The reader provides a page indicator, Go to Page, thumbnails and outline sidebar, Find, Print, remembered position, single/two-page layouts, and full screen. Zoom tracks fit and manual modes separately so view updates do not reset the user's zoom. Printing includes the visible signature placements through the export path.

## Privacy and file access

The app is sandboxed with user-selected read/write file access and no network entitlement. User-selected import/export URLs use security-scoped access where needed. Signature profiles remain on this Mac. PDF data and signature images still require validation at their input boundaries; using Swift does not eliminate risks in document parsing.

## Packaging and distribution

`build_app.sh` builds with SwiftPM using stock macOS Bash 3.2, locates the executable through SwiftPM, and packages `PDFView.app`. It copies the Info.plist template, app icon, and sandbox entitlements, patches version metadata, and signs the executable and bundle. `ARCHES="arm64 x86_64"` produces a universal executable before signing.

`scripts/make-icon.swift` draws the icon procedurally with Core Graphics, exports the standard iconset resolutions, and invokes `iconutil`. The committed `Resources/AppIcon.icns` is the packaging input; regeneration requires only Swift and the macOS SDK.

Ad-hoc signing is the default. Optional Developer ID notarization submits a `ditto` ZIP, checks for Accepted, staples and validates the app, and rebuilds the ZIP with the ticket. The tag release workflow currently distributes an ad-hoc signed app and documents the appropriate Gatekeeper override for each macOS version.

## Verification

Swift Testing covers document/export behavior, signature rendering/storage, and interaction logic as the corresponding slices land. Bundle checks cover Bash compatibility, resources, architectures, metadata, and signature integrity. CI and release use the same pinned SwiftLint/SwiftFormat workflow; lint never rewrites the checkout.

On-screen verification remains necessary for menu routing, scrolling/zoom overlays, accessibility, multiwindow behavior, and first-launch Gatekeeper dialogs. Local builds and rendered bitmap checks do not establish that these UI flows or Apple's live notarization service succeeded.
