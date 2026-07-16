import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Color {
    init(hexRGB: String) {
        let value = hexRGB.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else {
            self = .black
            return
        }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    var hexRGB: String {
        let components: (red: CGFloat, green: CGFloat, blue: CGFloat)
#if os(macOS)
        guard let color = NSColor(self).usingColorSpace(.sRGB) else {
            return "#000000"
        }
        components = (color.redComponent, color.greenComponent, color.blueComponent)
#else
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: nil) else {
            return "#000000"
        }
        components = (red, green, blue)
#endif
        return String(
            format: "#%02X%02X%02X",
            Int((components.red * 255).rounded()),
            Int((components.green * 255).rounded()),
            Int((components.blue * 255).rounded())
        )
    }
}
