import AppKit
@preconcurrency import Quartz
import SwiftUI

/// Main content view for PDF documents
/// Provides the SwiftUI interface wrapping the PDFKit view
struct PDFContentView: View {
    /// The document binding from DocumentGroup
    @Binding var document: PDFViewerDocument
    /// The file this window shows; drives the signed copy's default name and folder.
    let fileURL: URL?

    @Environment(\.undoManager)
    private var undoManager
    @EnvironmentObject private var signatureStore: SignatureStore
    @Environment(StampSizeMemory.self)
    private var stampSizes

    @State private var reader = ReaderController()
    @State private var export = SignedCopyOperation()
    @State private var printTask: Task<Void, Never>?
    @State private var zoom: ZoomState = .fit
    @State private var viewer = PDFViewerProxy()
    @State private var editor = SignaturePlacementEditor()
    @State private var closeGuard = DocumentCloseGuard()

    @State private var protectionSession = DocumentProtectionSession()
    @State private var stampKind: StampKind = .signature
    @State private var setupKind: SignatureKind = .signature
    @State private var signingMode: SigningMode = .idle
    /// Fields or Anywhere, per stamp kind, for this window.
    @State private var placementChoices = PlacementChoices()
    /// Nil until the PDF view has scanned the document.
    @State private var documentState: PDFKitView.DocumentState?
    @State private var lastFieldIndex: Int?
    @State private var exportedPlacements: [PDFViewerDocument.SignaturePlacement]?
    /// Live, initial and last-exported form values; the baseline is captured before editing.
    @State private var formValues: [FormFieldValue]?
    @State private var originalFormValues: [FormFieldValue]?
    @State private var savedFormValues: [FormFieldValue]?
    /// The last signed copy saved from this window; File menu sharing stays bound to it.
    @State private var lastSavedURL: URL?
    @State private var showsSavedBanner = false
    /// Why the last action did nothing, or what it did when nothing else on screen shows it.
    @State private var notice = TransientNotice()

    @State private var showSignatureSetupSheet = false
    @State private var isEditingSignature = false
    /// Why the setup sheet is open on the way to a stamp, and what Cancel goes back to.
    @State private var setupRequest: SetupRequest?
    /// The saved profile the Delete Saved Signature/Initials… alert is asking about.
    @State private var profileToDelete: SignatureKind?
    @State private var errorAlert: ErrorAlert?

    var body: some View {
        window
            .alert(errorAlert?.title ?? "", isPresented: errorAlertIsPresented, presenting: errorAlert) { _ in
                Button("OK", role: .cancel) {}
            } message: { alert in
                Text(alert.message)
            }
            .onChange(of: document.pdfDocument.map(ObjectIdentifier.init), initial: true) { _, _ in
                synchronizeDocument()
            }
            .onExitCommand(perform: handleEscape)
            .onDisappear {
                reader.persist()
                export.cancel()
                printTask?.cancel()
            }
            .onChange(of: unsavedWork) { _, work in
                closeGuard.isEdited = !work.isEmpty
            }
            .onChange(of: reader.find.isVisible) { _, isVisible in
                if !isVisible {
                    viewer.focusDocument()
                }
            }
            .focusedSceneValue(\.signingActions, signingActions)
            .focusedSceneValue(\.zoomActions, zoomActions)
            .focusedSceneValue(\.readerActions, ReaderCommandActions(
                reader: reader,
                isBusy: export.isBusy,
                printDocument: printDocument,
                pageSetup: runPageSetup,
                hasFormFields: formValues?.isEmpty == false,
                moveToFormField: moveToFormField
            ))
    }

    private var window: some View {
        @Bindable var reader = reader
        @Bindable var protectionSession = protectionSession
        return content
            .sheet(isPresented: $reader.showGoToPage) { GoToPageSheet(reader: reader) }
            .frame(minWidth: 600, minHeight: 400)
            .toolbar {
                toolbarContent
            }
            .toolbarRole(.editor)
            .sheet(isPresented: $protectionSession.showsUnlock) {
                if let protection = protectionSession.protection {
                    UnlockDocumentSheet(
                        protection: protection,
                        onUnlock: {
                            protectionSession.refresh()
                            reader.refresh()
                            viewer.focusDocumentWhenShown()
                        },
                        onCancel: { protectionSession.showsUnlock = false }
                    )
                }
            }
            .sheet(isPresented: $showSignatureSetupSheet) {
                signatureSetupSheet
            }
            .alert(
                StampWorkflow.deleteAlertTitle(profileToDelete ?? .signature),
                isPresented: deleteAlertIsPresented,
                presenting: profileToDelete
            ) { kind in
                Button("Delete", role: .destructive) { deleteProfile(kind) }
                Button("Cancel", role: .cancel) {}
            } message: { kind in
                Text(StampWorkflow.deleteAlertMessage(kind))
            }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if let progress = export.progress {
                ExportProgressBanner(
                    progress: progress,
                    purpose: printTask == nil ? .signedCopy : .print,
                    cancel: cancelExport
                )
            }
            if isLocked {
                HStack {
                    Text("This PDF is locked. Unlock it to read, sign, save a signed copy, or print.")
                    Spacer()
                    Button("Unlock…", action: protectionSession.requestUnlock)
                }
                .font(.callout)
                .padding(12)
                .background(.bar)
            }
            if signingMode != .idle {
                signingBanner
            } else {
                if let message = notice.text {
                    noticeBanner(message)
                }
                if isSavedBannerVisible, let lastSavedURL {
                    savedBanner(for: lastSavedURL)
                }
            }

            if reader.find.isVisible {
                FindBar(find: reader.find, onEscape: closeFind)
            }
            // The locked banner already says printing needs the password.
            if !isLocked, let reason = reader.printDisabledReason {
                Text(reason).font(.callout).foregroundStyle(.secondary).padding(4)
            }
            HSplitView {
                if reader.sidebarVisible {
                    ReaderSidebar(reader: reader)
                }
                pdfView
            }
        }
    }

    private var pdfView: some View {
        PDFKitView(
            document: Self.documentForPageView(document.pdfDocument, protection: protectionSession.protection),
            signaturePlacements: document.signaturePlacements,
            zoom: $zoom,
            signingMode: signingMode,
            stampPNGData: signingMode == .idle ? nil : activeArtwork?.pngData,
            stampWidth: stampSizes.width(for: stampKind),
            viewer: viewer,
            reader: reader,
            fileURL: fileURL,
            onEscape: handleEscape,
            onStopSigning: exitSigning,
            isExporting: export.progress != nil,
            isShowingSavedBanner: isSavedBannerVisible,
            onWindow: attachCloseGuard,
            onPlaceSignature: placeSignature,
            onUpdatePlacementBounds: updatePlacementBounds,
            onDeletePlacement: { configuredEditor().delete(id: $0) },
            onDocumentStateChange: applyDocumentState,
            onFormValuesChange: applyFormValues,
            onNotice: showNotice
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isLocked {
                ContentUnavailableView(
                    "This PDF Is Locked",
                    systemImage: "lock",
                    description: Text("Unlock it to see its pages.")
                )
            }
        }
    }

    /// PDFKit shows its own password field for a locked document, which would give the window two
    /// unlock surfaces; it gets no document until the unlock sheet has opened it.
    static func documentForPageView(_ document: PDFDocument?, protection: DocumentProtection?) -> PDFDocument? {
        let isLocked = protection?.isLocked ?? document?.isLocked ?? false
        return isLocked ? nil : document
    }
}

extension PDFContentView {
    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { reader.sidebarVisible.toggle() } label: {
                Label("Toggle Sidebar", systemImage: "sidebar.left")
            }
            .help("Show or hide the document sidebar")
        }
        ToolbarItem(placement: .principal) {
            Button { reader.showGoToPage = true } label: { Text(reader.pageIndicator).monospacedDigit() }
                .disabled(!reader.canRead)
                .accessibilityLabel("Current page")
                .accessibilityValue(reader.pageIndicator)
                .help("Go to Page…")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                Button(action: zoomOut) {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .help("Zoom Out")

                Button(action: zoomIn) {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                // The View menu item shows ⌘+; this accepts the unshifted ⌘= as well.
                .keyboardShortcut("=", modifiers: .command)
                .help("Zoom In")
            } label: {
                Label("Zoom", systemImage: "plus.magnifyingglass")
            }

            Button(action: zoomToFit) {
                Label("Zoom to Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
            }
            .help("Zoom to Fit")

            Menu {
                ForEach(StampKind.allCases) { kind in
                    Button("Place \(kind.title)") { chooseStamp(kind) }
                }
                if signingMode != .idle {
                    Divider()
                    Button(StampWorkflow.signingToggleTitle(mode: signingMode, kind: stampKind), action: exitSigning)
                }
            } label: {
                Label("Sign", systemImage: StampWorkflow.signToolbarSymbol(mode: signingMode))
            }
            .foregroundStyle(signingMode == .idle ? Color.primary : Color.accentColor)
            .disabled(!canSign)
            .help("Place a signature, initials, or today's date")
            .accessibilityValue(StampWorkflow.signToolbarValue(mode: signingMode))
            .accessibilityHint("Choose Signature, Initials, or Date, then click to place. Done stops signing.")

            Button {
                saveSignedCopy()
            } label: {
                Label("Save Signed Copy…", systemImage: "square.and.arrow.down")
            }
            .disabled(!canSaveSignedCopy)
            .help("Save Signed Copy…")
            .accessibilityHint("Saves a copy of the PDF with your signature stamps flattened in.")
        }
    }

    private var signingBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "signature")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            // A notice stands in for the instruction while it shows, so the banner does not grow.
            if let message = notice.text {
                Label(message, systemImage: "exclamationmark.circle")
            } else {
                Text(SigningFlowLogic.statusText(mode: signingMode, kind: stampKind))
            }
            Spacer()
            if hasSignatureFields {
                Picker("Place stamp in", selection: anywhereSelection) {
                    Text("Fields").tag(false)
                    Text("Anywhere").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Button("Done", action: exitSigning)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func noticeBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Label(message, systemImage: "exclamationmark.circle")
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func savedBanner(for url: URL) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(SigningFlowLogic.savedText(for: url))
            Spacer()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            ShareLink(item: url) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Button(action: dismissSavedBanner) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Close")
            .help("Close (Esc). File > Share Signed Copy… (⌥⇧⌘E) and Show Signed Copy in Finder (⇧⌘R) stay available.")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
        // The banner stays until closed, so there is time to read it and to reach its buttons.
        .onExitCommand(perform: dismissSavedBanner)
    }

    private func dismissSavedBanner() {
        showsSavedBanner = false
        viewer.focusDocument()
    }

    private var signatureSetupSheet: some View {
        SignatureSetupSheet(
            existingProfile: isEditingSignature ? signatureStore.profile(for: setupKind) : nil,
            kind: setupKind,
            fullName: signatureStore.profile?.fullName ?? signatureStore.profile(for: .initials)?.fullName ?? "",
            onCancel: {
                showSignatureSetupSheet = false
                let restored = (setupRequest ?? SetupRequest(restoring: currentSigningState)).stateAfterCancel
                setupRequest = nil
                stampKind = restored.kind
                signingMode = restored.mode
            },
            onSave: { profile in
                do {
                    try signatureStore.saveProfile(profile, for: setupKind)
                    showSignatureSetupSheet = false
                    let pending = setupRequest?.pending
                    setupRequest = nil
                    switch pending {
                    case let .enter(mode)?: enterSigning(mode)
                    case .placeInNextField?: placeInNextField()
                    case .placeOnCurrentPage?: placeOnCurrentPage()
                    case .placeInitialsOnEveryPage?: placeInitialsOnEveryPage()
                    case nil: break
                    }
                } catch {
                    errorAlert = ErrorAlert(title: "Couldn’t Save \(setupKind.title)", error: error)
                }
            }
        )
    }

    // MARK: State

    private var errorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { errorAlert != nil },
            set: {
                if !$0 {
                    errorAlert = nil
                }
            }
        )
    }

    private var deleteAlertIsPresented: Binding<Bool> {
        Binding(
            get: { profileToDelete != nil },
            set: {
                if !$0 {
                    profileToDelete = nil
                }
            }
        )
    }

    private var anywhereSelection: Binding<Bool> {
        Binding(
            get: { signingMode == .freePlacement },
            set: setAnywhere
        )
    }

    private var signatureFields: [SignatureField] {
        documentState?.signatureFields ?? []
    }

    private var isSavedBannerVisible: Bool {
        showsSavedBanner && lastSavedURL != nil && signingMode == .idle
    }

    private var isLocked: Bool {
        protectionSession.protection?.isLocked ?? document.pdfDocument?.isLocked ?? false
    }

    private var hasSignatureFields: Bool {
        !signatureFields.isEmpty
    }

    private var canSign: Bool {
        guard let pdf = document.pdfDocument, pdf.pageCount > 0 else { return false }
        return !pdf.isLocked && documentState?.isLocked == false && !export.isBusy
    }

    private var canSaveSignedCopy: Bool {
        document.pdfDocument?.isLocked == false && protectionSession.protection != nil
            && !export.isBusy && SigningFlowLogic.hasSignedCopyContent(
                placements: document.signaturePlacements,
                formValues: formValues,
                originalFormValues: originalFormValues
            )
    }

    private var unsavedWork: UnsavedWork {
        unsavedWork(formValues: formValues)
    }

    private func unsavedWork(formValues: [FormFieldValue]?) -> UnsavedWork {
        SigningFlowLogic.unsavedWork(
            placements: document.signaturePlacements,
            exported: exportedPlacements,
            formValues: formValues,
            savedFormValues: savedFormValues
        )
    }

    private var activeArtwork: StampArtwork? {
        StampArtwork.make(
            kind: stampKind,
            signature: signatureStore.profile,
            initials: signatureStore.profile(for: .initials)
        )
    }

    private var signatureImageSize: CGSize? {
        activeArtwork?.imageSize
    }

    private var signingActions: SigningCommandActions {
        SigningCommandActions(
            signingMode: signingMode,
            stampKind: stampKind,
            canSign: canSign,
            hasSignatureFields: hasSignatureFields,
            canSaveSignedCopy: canSaveSignedCopy,
            toggleSigning: toggleSigning,
            placeInNextField: placeInNextField,
            placeOnCurrentPage: placeOnCurrentPage,
            placeInitialsOnEveryPage: placeInitialsOnEveryPage,
            setAnywhere: setAnywhere,
            hasPlacements: !document.signaturePlacements.isEmpty,
            selectNextSignature: { selectAdjacentSignature(forward: true) },
            selectPreviousSignature: { selectAdjacentSignature(forward: false) },
            saveSignedCopy: { saveSignedCopy() },
            lastSavedURL: lastSavedURL,
            shareSignedCopy: { url in viewer.showSharingPicker(for: url) },
            editSignature: editSignature,
            deleteProfile: { profileToDelete = $0 },
            placeStamp: chooseStamp,
            editInitials: { editProfile(.initials) },
            canUnlock: protectionSession.protection?.isLocked == true,
            unlock: protectionSession.requestUnlock
        )
    }

    private var zoomActions: ZoomCommandActions {
        ZoomCommandActions(
            actualSize: { zoom = .actualSize },
            zoomToFit: zoomToFit,
            zoomIn: zoomIn,
            zoomOut: zoomOut
        )
    }

    private func applyFormValues(_ values: [FormFieldValue]) {
        formValues = values
    }

    private func applyDocumentState(_ state: PDFKitView.DocumentState) {
        synchronizeDocument()
        protectionSession.refresh()
        reader.refresh()
        documentState = state
        formValues = protectionSession.protection?.formBaseline?.values() ?? state.formValues
        if originalFormValues == nil {
            originalFormValues = protectionSession.protection?.initialFormValues
            savedFormValues = originalFormValues
        }
        lastFieldIndex = nil
        signingMode = state.isLocked ? .idle :
            SigningFlowLogic.refreshed(signingMode, hasSignatureFields: !state.signatureFields.isEmpty)
    }

    private func synchronizeDocument() {
        guard protectionSession.protection?.document !== document.pdfDocument else { return }
        protectionSession.attach(
            document.pdfDocument, formBaseline: document.formBaseline, initialFormValues: document.initialFormValues
        )
        documentState = nil
        signingMode = .idle
        stampKind = .signature
        setupRequest = nil
        showSignatureSetupSheet = false
        lastFieldIndex = nil
        exportedPlacements = nil
        formValues = protectionSession.protection?.formBaseline?.values()
        originalFormValues = protectionSession.protection?.initialFormValues
        savedFormValues = originalFormValues
        lastSavedURL = nil
        showsSavedBanner = false
    }
}

// MARK: Actions

extension PDFContentView {
    private func zoomIn() {
        zoom = ZoomState.zoomedIn(from: viewer.displayedScale)
    }

    private func zoomOut() {
        zoom = ZoomState.zoomedOut(from: viewer.displayedScale)
    }

    private func zoomToFit() {
        zoom = .fit
    }

    // MARK: Signing

    private func toggleSigning() {
        if signingMode == .idle {
            startSigning(placementChoices.entryMode(for: stampKind, hasSignatureFields: hasSignatureFields))
        } else {
            exitSigning()
        }
    }

    private func chooseStamp(_ kind: StampKind) {
        guard canSign else { return }
        let previous = currentSigningState
        stampKind = kind
        startSigning(placementChoices.entryMode(for: kind, hasSignatureFields: hasSignatureFields), restoring: previous)
    }

    /// Enters signing, first asking the user to create a signature if there is none yet.
    /// `previous` is what cancelling that setup returns to, when the caller already changed the kind.
    private func startSigning(_ mode: SigningMode, restoring previous: SigningState? = nil) {
        guard canSign else { return }
        guard activeArtwork != nil else {
            requestSignatureSetup(then: .enter(mode), restoring: previous)
            return
        }
        enterSigning(mode)
    }

    private var currentSigningState: SigningState {
        SigningState(kind: stampKind, mode: signingMode)
    }

    /// Asks for a signature first; the requested action runs once the sheet saves.
    private func requestSignatureSetup(
        then action: PendingSigningAction,
        restoring previous: SigningState? = nil,
        kind: SignatureKind? = nil
    ) {
        guard let kind = kind ?? stampKind.profileKind else { return }
        setupKind = kind
        isEditingSignature = false
        setupRequest = SetupRequest(pending: action, restoring: previous ?? currentSigningState)
        showSignatureSetupSheet = true
    }

    private func enterSigning(_ mode: SigningMode) {
        guard canSign else { return }
        viewer.select(placementID: nil)
        signingMode = mode
        announce(SigningFlowLogic.enteredAnnouncement(mode: mode, kind: stampKind))
    }

    private func exitSigning() {
        guard signingMode != .idle else { return }
        signingMode = SigningFlowLogic.exited(signingMode)
        stampKind = StampWorkflow.kindAfterPlacementOrExit(stampKind)
        notice.dismiss()
        announce(SigningFlowLogic.exitedAnnouncement)
        // The Done button that may have had focus is gone; give focus back to the document.
        viewer.focusDocument()
    }

    private func setAnywhere(_ anywhere: Bool) {
        placementChoices.remember(anywhere: anywhere, for: stampKind)
        let mode = SigningFlowLogic.mode(anywhere: anywhere, hasSignatureFields: hasSignatureFields)
        if signingMode == .idle {
            startSigning(mode)
        } else {
            signingMode = mode
        }
    }

    /// Keyboard path to field signing: each use fills the next detected signature field.
    private func placeInNextField() {
        guard canSign else { return }
        if let reason = SigningFlowLogic.nextFieldUnavailableReason(
            kind: stampKind,
            hasSignatureFields: hasSignatureFields
        ) {
            showNotice(reason)
            return
        }
        guard let imageSize = signatureImageSize else {
            requestSignatureSetup(then: .placeInNextField)
            return
        }
        guard let index = StampWorkflow.nextEmptyFieldIndex(
            after: lastFieldIndex,
            fields: signatureFields,
            placements: document.signaturePlacements
        ) else {
            showNotice(StampWorkflow.allFieldsFilledAnnouncement)
            return
        }
        guard let page = document.pdfDocument?.page(at: signatureFields[index].pageIndex) else { return }

        let field = signatureFields[index]
        lastFieldIndex = index
        let cropBox = page.bounds(for: .cropBox)
        let bounds = PlacementGeometry.aspectFit(
            imageSize: imageSize,
            in: PlacementGeometry.clamped(field.bounds, to: cropBox)
        )
        viewer.reveal(field.bounds, onPageAt: field.pageIndex)
        placeSignature(pageIndex: field.pageIndex, bounds: bounds)
    }

    /// Keyboard path to free signing: a centred stamp, then arrow keys move it.
    private func placeOnCurrentPage() {
        guard canSign else { return }
        guard let imageSize = signatureImageSize else {
            requestSignatureSetup(then: .placeOnCurrentPage)
            return
        }
        let pageIndex = viewer.currentPageIndex ?? 0
        guard let page = document.pdfDocument?.page(at: pageIndex) else { return }

        let cropBox = page.bounds(for: .cropBox)
        let bounds = PlacementGeometry.defaultRect(
            centeredAt: CGPoint(x: cropBox.midX, y: cropBox.midY),
            imageSize: imageSize,
            pageBounds: cropBox,
            width: stampSizes.width(for: stampKind)
        )
        viewer.reveal(bounds, onPageAt: pageIndex)
        placeSignature(pageIndex: pageIndex, bounds: bounds)
    }

    /// One undoable step that initials every page that has none, at the position of the selected or
    /// last initials, or in the bottom-right margin.
    private func placeInitialsOnEveryPage() {
        guard canSign, let pdf = document.pdfDocument else { return }
        let artwork = StampArtwork.make(
            kind: .initials,
            signature: nil,
            initials: signatureStore.profile(for: .initials)
        )
        guard let artwork, let imageSize = artwork.imageSize else {
            requestSignatureSetup(then: .placeInitialsOnEveryPage, kind: .initials)
            return
        }
        let pages = (0 ..< pdf.pageCount).map { index in
            pdf.page(at: index)
                .map { StampWorkflow.PageFrame(cropBox: $0.bounds(for: .cropBox), rotation: $0.rotation) }
                ?? StampWorkflow.PageFrame(cropBox: .zero)
        }
        let targets = StampWorkflow.initialsOnEveryPage(
            reference: StampWorkflow.referenceInitials(
                selectedID: viewer.selectedPlacementID,
                placements: document.signaturePlacements
            ),
            pages: pages,
            placements: document.signaturePlacements,
            defaultSize: PlacementGeometry.defaultSize(imageSize: imageSize, width: stampSizes.width(for: .initials))
        )
        if !targets.isEmpty {
            let placements = targets.map { artwork.placement(pageIndex: $0.pageIndex, bounds: $0.bounds) }
            configuredEditor().add(placements, actionName: StampWorkflow.everyPageActionName)
            signingMode = .idle
            stampKind = StampWorkflow.kindAfterPlacementOrExit(stampKind)
        }
        showNotice(StampWorkflow.everyPageAnnouncement(count: targets.count))
    }

    private func placeSignature(pageIndex: Int, bounds: CGRect) {
        guard canSign, let artwork = activeArtwork else { return }
        let placement = artwork.placement(pageIndex: pageIndex, bounds: bounds)
        configuredEditor().add(placement)
        signingMode = SigningFlowLogic.afterPlacement(signingMode)
        viewer.select(placementID: placement.id)
        let location = viewer.location(of: bounds, onPageAt: pageIndex) ?? ""
        announce(StampAccessibility.placedAnnouncement(pageIndex: pageIndex, location: location, kind: artwork.kind))
        stampKind = StampWorkflow.kindAfterPlacementOrExit(artwork.kind)
    }

    /// Select Next/Previous Signature: reveals the stamp, gives it keyboard focus and reads its label.
    private func selectAdjacentSignature(forward: Bool) {
        let placements = document.signaturePlacements
        guard let id = SigningFlowLogic.adjacentPlacement(
            after: viewer.selectedPlacementID,
            in: placements,
            forward: forward
        ), let placement = placements.first(where: { $0.id == id }) else { return }
        viewer.reveal(placement.bounds, onPageAt: placement.pageIndex)
        viewer.select(placementID: id)
        if let label = viewer.label(for: placement) {
            announce(label)
        }
    }

    /// A resize also sets the size the next stamp of that kind is placed at.
    private func updatePlacementBounds(id: UUID, to bounds: CGRect, actionName: String) {
        let placement = document.signaturePlacements.first { $0.id == id }
        if let placement, placement.bounds.width != bounds.width {
            stampSizes.remember(width: bounds.width, for: placement.kind)
        }
        configuredEditor().setBounds(id: id, to: bounds, actionName: actionName)
    }

    private func configuredEditor() -> SignaturePlacementEditor {
        editor.document = $document
        editor.undoManager = undoManager
        return editor
    }

    /// Edits the saved signature, or creates one when there is none yet.
    private func editSignature() {
        editProfile(.signature)
    }

    private func editProfile(_ kind: SignatureKind) {
        setupKind = kind
        isEditingSignature = signatureStore.profile(for: kind) != nil
        setupRequest = nil
        showSignatureSetupSheet = true
    }

    private func deleteProfile(_ kind: SignatureKind) {
        do {
            try signatureStore.deleteProfile(for: kind)
            if stampKind.profileKind == kind {
                signingMode = .idle
                stampKind = .signature
            }
        } catch {
            errorAlert = ErrorAlert(title: "Couldn’t Delete \(kind.title)", error: error)
        }
    }

    // MARK: Saving

    /// Asks for a destination in a sheet on this document's window, then writes the signed copy.
    private func saveSignedCopy(completion: @escaping (Bool) -> Void = { _ in }) {
        viewer.refreshFormValues()
        guard canSaveSignedCopy, let protection = protectionSession.protection,
              let source = document.pdfDocument, let window = viewer.window, export.reserve()
        else {
            completion(false)
            return
        }
        let panel = NSSavePanel()
        export.configure(panel, originalURL: fileURL, protection: protection)
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = SigningFlowLogic.signedFileName(for: fileURL)
        panel.directoryURL = fileURL?.deletingLastPathComponent()
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url, document.pdfDocument === source else {
                export.release()
                completion(false)
                return
            }
            let placements = document.signaturePlacements
            export.write(source, placements: placements, to: url) { result in
                switch result {
                case let .success(state):
                    exportedPlacements = state.placements
                    savedFormValues = state.formValues
                    lastSavedURL = url
                    showsSavedBanner = true
                    announce(SigningFlowLogic.savedAnnouncement(for: url))
                    formValues = FormScan.capture(source)?.values()
                    closeGuard.isEdited = document.pdfDocument !== source || !state.matches(
                        placements: document.signaturePlacements, formValues: formValues
                    )
                    completion(!closeGuard.isEdited)
                case let .failure(error):
                    reportSaveFailure(error)
                    completion(false)
                }
            }
        }
    }

    private func reportSaveFailure(_ error: Error) {
        if !(error is CancellationError) {
            errorAlert = ErrorAlert(title: "Couldn’t Save Signed Copy", error: error)
        }
    }

    private func printDocument() {
        guard reader.canPrint, let source = document.pdfDocument, export.reserve() else { return }
        let placements = document.signaturePlacements
        let selected = protectionSession.protection?.exportPassword
        printTask = Task {
            let printing = PDFPrinting()
            defer {
                printing.cleanup()
                export.release()
                printTask = nil
            }
            do {
                try await printing.prepare(source: source, placements: placements, password: selected) {
                    export.updateProgress($0)
                }
                try Task.checkCancellation()
                try printing.run()
            } catch {
                if !(error is CancellationError) {
                    errorAlert = ErrorAlert(title: "Couldn’t Print PDF", error: error)
                }
            }
        }
    }

    /// Page Setup as a sheet on this window; the print panel itself is run by `PDFPrinting`.
    private func runPageSetup() {
        guard let window = viewer.window else { return }
        NSPageLayout().beginSheet(using: NSPrintInfo.shared, on: window, completionHandler: nil)
    }

    private func cancelExport() {
        export.cancel()
        printTask?.cancel()
    }

    private func handleEscape() {
        let action = SigningFlowLogic.escapeAction(
            isExporting: export.progress != nil,
            isSigning: signingMode != .idle,
            isFindVisible: reader.find.isVisible,
            hasSelection: viewer.selectedPlacementID != nil,
            isSavedBannerVisible: isSavedBannerVisible
        )
        switch action {
        case .cancelExport: cancelExport()
        case .stopSigning: exitSigning()
        case .closeFind: closeFind()
        case .deselect: viewer.select(placementID: nil)
        case .closeSavedBanner: dismissSavedBanner()
        case .none: break
        }
    }

    private func moveToFormField(forward: Bool) {
        guard let message = viewer.moveToFormField(forward: forward) else {
            showNotice(FormFieldNavigation.noFieldsAnnouncement)
            return
        }
        announce(message)
    }

    private func closeFind() {
        reader.find.close()
        viewer.focusDocument()
    }

    private func attachCloseGuard(to window: NSWindow) {
        closeGuard.documentName = fileURL?.lastPathComponent ?? "this document"
        closeGuard.saveSignedCopy = { completion in saveSignedCopy(completion: completion) }
        closeGuard.unsavedWork = {
            unsavedWork(formValues: protectionSession.protection?.formBaseline?.values())
        }
        closeGuard.install(on: window)
        closeGuard.isEdited = !unsavedWork.isEmpty
    }

    /// Shows a message in the banner for a few seconds and reads it to VoiceOver, instead of a beep.
    private func showNotice(_ message: String) {
        notice.show(message)
        announce(message)
    }

    private func announce(_ message: String) {
        NSAccessibility.post(
            element: viewer.window ?? NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }
}

/// Adds, moves, resizes and deletes placements on the document model, registering each change
/// with the window's undo manager under a user-facing action name.
@MainActor
final class SignaturePlacementEditor {
    var document: Binding<PDFViewerDocument>?
    weak var undoManager: UndoManager?

    func add(_ placement: PDFViewerDocument.SignaturePlacement) {
        insert(placement, at: nil, actionName: placement.kind.actionName(.add))
    }

    /// Several stamps as one undoable step, e.g. Place Initials on Every Page.
    func add(_ placements: [PDFViewerDocument.SignaturePlacement], actionName: String) {
        undoManager?.beginUndoGrouping()
        for placement in placements {
            insert(placement, at: nil, actionName: actionName)
        }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName(actionName)
    }

    func delete(id: UUID) {
        let kind = document?.wrappedValue.signaturePlacements.first { $0.id == id }?.kind ?? .signature
        remove(id: id, actionName: kind.actionName(.remove))
    }

    func setBounds(id: UUID, to bounds: CGRect, actionName: String) {
        guard let document,
              let current = document.wrappedValue.signaturePlacements.first(where: { $0.id == id }),
              current.bounds != bounds,
              let previous = document.wrappedValue.updatePlacementBounds(id: id, to: bounds)
        else {
            return
        }
        registerUndo(actionName) { $0.setBounds(id: id, to: previous, actionName: actionName) }
    }

    private func insert(_ placement: PDFViewerDocument.SignaturePlacement, at index: Int?, actionName: String) {
        guard let document else { return }
        if let index {
            document.wrappedValue.insertSignaturePlacement(placement, at: index)
        } else {
            document.wrappedValue.addSignaturePlacement(placement)
        }
        registerUndo(actionName) { $0.remove(id: placement.id, actionName: actionName) }
    }

    private func remove(id: UUID, actionName: String) {
        guard let document,
              let index = document.wrappedValue.signaturePlacements.firstIndex(where: { $0.id == id }),
              let removed = document.wrappedValue.removeSignaturePlacement(id: id)
        else {
            return
        }
        registerUndo(actionName) { $0.insert(removed, at: index, actionName: actionName) }
    }

    private func registerUndo(_ actionName: String, _ undo: @escaping @MainActor (SignaturePlacementEditor) -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            // UndoManager invokes handlers on the main thread; assumeIsolated satisfies Swift 6 MainActor checking.
            MainActor.assumeIsolated {
                undo(target)
            }
        }
        undoManager.setActionName(actionName)
    }
}

/// Window delegate shim that asks before closing a window whose signatures were not saved.
/// Every other delegate message is forwarded to the delegate SwiftUI installed.
@MainActor
final class DocumentCloseGuard: NSObject, NSWindowDelegate {
    // swiftlint:disable:next modifier_order
    private nonisolated(unsafe) static var associationKey: UInt8 = 0

    var documentName = "this document"
    var saveSignedCopy: (@escaping (Bool) -> Void) -> Void = { $0(false) }
    /// Asked at decision time: PDFKit may hold a form edit the window has not been told about yet.
    var unsavedWork: () -> UnsavedWork = { UnsavedWork() }

    /// Mirrors unsaved signatures and form entries into the window's edited dot.
    var isEdited = false {
        didSet { window?.isDocumentEdited = isEdited }
    }

    private weak var window: NSWindow?
    // swiftlint:disable:next modifier_order
    private nonisolated(unsafe) weak var originalDelegate: NSWindowDelegate?
    private var isCloseConfirmed = false

    static func installed(on window: NSWindow) -> DocumentCloseGuard? {
        objc_getAssociatedObject(window, &associationKey) as? DocumentCloseGuard
    }

    func install(on window: NSWindow) {
        self.window = window
        window.isDocumentEdited = isEdited
        guard window.delegate !== self else { return }
        originalDelegate = window.delegate
        window.delegate = self
        // The window holds the delegate weakly; tie the shim's lifetime to the window.
        objc_setAssociatedObject(window, &Self.associationKey, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    override nonisolated func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || originalDelegate?.responds(to: aSelector) == true
    }

    override nonisolated func forwardingTarget(for aSelector: Selector!) -> Any? {
        originalDelegate?.responds(to: aSelector) == true ? originalDelegate : nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let work = unsavedWork()
        if !work.isEmpty, !isCloseConfirmed {
            confirmClose(of: sender, work: work)
            return false
        }
        return originalDelegate?.windowShouldClose?(sender) ?? true
    }

    private func confirmClose(of window: NSWindow, work: UnsavedWork) {
        askToSave(in: window, work: work, before: "closing") { [weak self, weak window] proceed in
            if proceed {
                self?.close(window)
            }
        }
    }

    /// Save Signed Copy… reports whether the save finished; Don’t Save proceeds; Cancel stops.
    private func askToSave(
        in window: NSWindow,
        work: UnsavedWork,
        before action: String,
        then done: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Save a signed copy of “\(documentName)” before \(action)?"
        alert.informativeText = work.lossWarning
        alert.addButton(withTitle: "Save Signed Copy…")
        let dontSave = alert.addButton(withTitle: "Don’t Save")
        dontSave.keyEquivalent = "d"
        dontSave.keyEquivalentModifierMask = .command
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                switch response {
                case .alertFirstButtonReturn:
                    if let save = self?.saveSignedCopy {
                        save(done)
                    } else {
                        done(false)
                    }
                case .alertSecondButtonReturn:
                    done(true)
                default:
                    done(false)
                }
            }
        }
    }

    private func close(_ window: NSWindow?) {
        isCloseConfirmed = true
        window?.performClose(nil)
    }
}

extension DocumentCloseGuard: QuitReviewable {
    var hasUnsavedWork: Bool {
        !unsavedWork().isEmpty
    }

    func reviewBeforeQuitting(then done: @escaping (Bool) -> Void) {
        guard let window else { return done(true) }
        window.makeKeyAndOrderFront(nil)
        askToSave(in: window, work: unsavedWork(), before: "quitting", then: done)
    }
}
