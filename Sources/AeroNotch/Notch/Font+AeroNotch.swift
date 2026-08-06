import SwiftUI
import AppKit

extension Font {
    /// The app's typeface: JetBrains Mono when installed, falling back to the
    /// system monospaced font. Weight maps to the family's named weights via
    /// PostScript names (deterministic — `.custom(_:size:).weight()` would
    /// lean on font matching).
    static func notch(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard JetBrainsMono.isAvailable else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return .custom(JetBrainsMono.postScriptName(for: weight), size: size)
    }
}

private enum JetBrainsMono {
    static let isAvailable: Bool = NSFont(name: "JetBrainsMono-Regular", size: 12) != nil

    static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin: return "JetBrainsMono-Thin"
        case .light: return "JetBrainsMono-ExtraLight"
        case .medium: return "JetBrainsMono-Medium"
        case .semibold: return "JetBrainsMono-SemiBold"
        case .bold, .heavy, .black: return "JetBrainsMono-Bold"
        default: return "JetBrainsMono-Regular"
        }
    }
}
