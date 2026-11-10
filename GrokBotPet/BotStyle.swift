import AppKit

struct BotColor: Equatable {
    let rgb: Int

    init(_ rgb: Int) {
        self.rgb = rgb
    }

    init?(nsColor: NSColor) {
        guard let color = nsColor.usingColorSpace(.sRGB) else { return nil }
        func channel(_ value: CGFloat) -> Int {
            Int((min(1, max(0, value)) * 255).rounded())
        }
        rgb = channel(color.redComponent) << 16
            | channel(color.greenComponent) << 8
            | channel(color.blueComponent)
    }

    var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat((rgb >> 16) & 255) / 255,
            green: CGFloat((rgb >> 8) & 255) / 255,
            blue: CGFloat(rgb & 255) / 255,
            alpha: 1
        )
    }

    var eyeColor: NSColor {
        let color = nsColor
        let brightness = 0.213 * color.redComponent + 0.715 * color.greenComponent + 0.072 * color.blueComponent
        return NSColor(white: brightness > 0.82 ? 0.16 : 0.99, alpha: 1)
    }

    var hexLabel: String {
        String(format: "#%06X", rgb)
    }
}

struct BotStyle: Equatable {
    var shape: BotShape
    var color: BotColor

    static let standard = Self(shape: .cloud, color: BotColor(0x15B8A3))

    static func load(from defaults: UserDefaults) -> Self {
        let shape = defaults.string(forKey: "botShape").flatMap(BotShape.init(rawValue:))
        let rgb = defaults.object(forKey: "botColor") as? Int
        let color = rgb.flatMap { (0...0xFFFFFF).contains($0) ? BotColor($0) : nil }
        return Self(shape: shape ?? standard.shape, color: color ?? standard.color)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(shape.rawValue, forKey: "botShape")
        defaults.set(color.rgb, forKey: "botColor")
    }
}
