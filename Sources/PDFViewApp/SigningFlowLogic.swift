import Foundation

enum SigningFlowLogic {
    static func entryMode(hasSignatureFields: Bool) -> SigningMode {
        hasSignatureFields ? .fieldPlacement : .freePlacement
    }

    static func toggledMode(current: SigningMode, hasSignatureFields: Bool) -> SigningMode {
        switch current {
        case .idle:
            return entryMode(hasSignatureFields: hasSignatureFields)
        case .fieldPlacement:
            return .freePlacement
        case .freePlacement:
            return hasSignatureFields ? .fieldPlacement : .freePlacement
        }
    }

    static func statusText(mode: SigningMode, hasSignatureFields: Bool) -> String {
        if hasSignatureFields {
            if mode.allowsFreePlacement {
                return "Visual signature stamp mode: click any page location to place your signature."
            }
            return "Visual signature stamp mode: click a signature field, or switch to free placement."
        }

        return "Visual signature stamp mode: no signature fields detected. Click anywhere to place your signature."
    }
}
