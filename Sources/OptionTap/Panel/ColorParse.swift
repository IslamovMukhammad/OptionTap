import SwiftUI

/// Turns colour text ("#2B4CFF", "rgb(43 76 255)", "hsl(230, 100%, 58%)") into a colour.
enum ColorParse {
    struct RGBA: Equatable {
        var r, g, b, a: Double
    }

    static func color(_ raw: String) -> Color? {
        components(raw).map { Color(.sRGB, red: $0.r, green: $0.g, blue: $0.b, opacity: $0.a) }
    }

    /// sRGB components in 0…1, or nil when the text isn't a colour.
    static func components(_ raw: String) -> RGBA? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("#") {
            var hex = String(text.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
            let hasAlpha = hex.count == 8
            return RGBA(r: Double((value >> (hasAlpha ? 24 : 16)) & 0xff) / 255,
                        g: Double((value >> (hasAlpha ? 16 : 8)) & 0xff) / 255,
                        b: Double((value >> (hasAlpha ? 8 : 0)) & 0xff) / 255,
                        a: hasAlpha ? Double(value & 0xff) / 255 : 1)
        }
        guard let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")"), open < close else { return nil }
        let numbers = text[text.index(after: open)..<close]
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .compactMap { Double($0.replacingOccurrences(of: "%", with: "")) }
        guard numbers.count >= 3 else { return nil }
        // Alpha may be written as 0.5 or 50%.
        let a = numbers.count > 3 ? (numbers[3] > 1 ? numbers[3] / 100 : numbers[3]) : 1
        if text.hasPrefix("rgb") {
            return RGBA(r: numbers[0] / 255, g: numbers[1] / 255, b: numbers[2] / 255, a: a)
        }
        if text.hasPrefix("hsl") {
            let h = numbers[0].truncatingRemainder(dividingBy: 360) / 360
            let s = numbers[1] / 100, l = numbers[2] / 100
            let q = l < 0.5 ? l * (1 + s) : l + s - l * s
            let p = 2 * l - q
            func channel(_ t: Double) -> Double {
                var t = t
                if t < 0 { t += 1 }
                if t > 1 { t -= 1 }
                if t < 1 / 6 { return p + (q - p) * 6 * t }
                if t < 1 / 2 { return q }
                if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
                return p
            }
            return RGBA(r: channel(h + 1 / 3), g: channel(h), b: channel(h - 1 / 3), a: a)
        }
        return nil
    }
}
