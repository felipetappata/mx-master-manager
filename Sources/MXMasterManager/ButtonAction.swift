import Foundation

enum ButtonAction: String, CaseIterable, Identifiable {
    case smartZoom, back, forward, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .smartZoom: return "Smart Zoom"
        case .back: return "Back (⌘[)"
        case .forward: return "Forward (⌘])"
        case .none: return "No action"
        }
    }
    var symbol: String {
        switch self {
        case .smartZoom: return "plus.magnifyingglass"
        case .back: return "arrow.left"
        case .forward: return "arrow.right"
        case .none: return "minus"
        }
    }
}
