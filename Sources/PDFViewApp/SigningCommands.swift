import SwiftUI

private struct StartSigningActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ToggleFreePlacementActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct SaveSignedCopyActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct SaveSignedCopyAsActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct UndoSignaturePlacementActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct RedoSignaturePlacementActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct CanUndoSignaturePlacementActionKey: FocusedValueKey {
    typealias Value = () -> Bool
}

private struct CanRedoSignaturePlacementActionKey: FocusedValueKey {
    typealias Value = () -> Bool
}

private struct EditSignatureActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct DeleteSignatureActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var startSigningAction: (() -> Void)? {
        get { self[StartSigningActionKey.self] }
        set { self[StartSigningActionKey.self] = newValue }
    }

    var toggleFreePlacementAction: (() -> Void)? {
        get { self[ToggleFreePlacementActionKey.self] }
        set { self[ToggleFreePlacementActionKey.self] = newValue }
    }

    var saveSignedCopyAction: (() -> Void)? {
        get { self[SaveSignedCopyActionKey.self] }
        set { self[SaveSignedCopyActionKey.self] = newValue }
    }

    var saveSignedCopyAsAction: (() -> Void)? {
        get { self[SaveSignedCopyAsActionKey.self] }
        set { self[SaveSignedCopyAsActionKey.self] = newValue }
    }

    var undoSignaturePlacementAction: (() -> Void)? {
        get { self[UndoSignaturePlacementActionKey.self] }
        set { self[UndoSignaturePlacementActionKey.self] = newValue }
    }

    var redoSignaturePlacementAction: (() -> Void)? {
        get { self[RedoSignaturePlacementActionKey.self] }
        set { self[RedoSignaturePlacementActionKey.self] = newValue }
    }

    var canUndoSignaturePlacementAction: (() -> Bool)? {
        get { self[CanUndoSignaturePlacementActionKey.self] }
        set { self[CanUndoSignaturePlacementActionKey.self] = newValue }
    }

    var canRedoSignaturePlacementAction: (() -> Bool)? {
        get { self[CanRedoSignaturePlacementActionKey.self] }
        set { self[CanRedoSignaturePlacementActionKey.self] = newValue }
    }

    var editSignatureAction: (() -> Void)? {
        get { self[EditSignatureActionKey.self] }
        set { self[EditSignatureActionKey.self] = newValue }
    }

    var deleteSignatureAction: (() -> Void)? {
        get { self[DeleteSignatureActionKey.self] }
        set { self[DeleteSignatureActionKey.self] = newValue }
    }
}
