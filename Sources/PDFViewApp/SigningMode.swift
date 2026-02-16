import Foundation

enum SigningMode: String {
    case idle
    case fieldPlacement
    case freePlacement

    var allowsFreePlacement: Bool {
        self == .freePlacement
    }
}
