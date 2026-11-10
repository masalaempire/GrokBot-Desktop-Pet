import SwiftUI

struct BotCustomizer: View {
    private struct Swatch {
        let title: String
        let color: BotColor

        init(_ title: String, _ rgb: Int) {
            self.title = title
            color = BotColor(rgb)
        }
    }

    private static let swatches = [
        Swatch("Black", 0x000000), Swatch("Brown", 0xA16C39),
        Swatch("Red", 0xFB2C3F), Swatch("Orange", 0xFE6A10),
        Swatch("Amber", 0xF69312), Swatch("Green", 0x13C16F),
        Swatch("Teal", 0x15B8A3), Swatch("Blue", 0x1E86FC),
        Swatch("Purple", 0x905AFA), Swatch("Pink", 0xF93498),
        Swatch("Gray", 0x959595)
    ]

    @State private var style: BotStyle
    private let onChange: (BotStyle) -> Void
    private let onClose: () -> Void

    init(style: BotStyle, onChange: @escaping (BotStyle) -> Void, onClose: @escaping () -> Void) {
        _style = State(initialValue: style)
        self.onChange = onChange
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            preview
            VStack(alignment: .leading, spacing: 9) {
                Text("Shape").font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 5), spacing: 7) {
                    ForEach(BotShape.allCases, id: \.self) { shape in
                        shapeButton(shape)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Color").font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 6), spacing: 5) {
                    ForEach(Self.swatches, id: \.color.rgb) { swatch in
                        colorButton(swatch)
                    }
                }
                ColorPicker("Custom color", selection: customColor, supportsOpacity: false)
            }
            Divider()
            HStack {
                Button("Reset", action: { style = .standard })
                    .disabled(style == .standard)
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 384)
        .fixedSize(horizontal: true, vertical: true)
        .onChange(of: style) { _, newStyle in onChange(newStyle) }
    }

    private var preview: some View {
        HStack(spacing: 12) {
            BotThumbnail(shape: style.shape, color: style.color)
                .frame(width: 74, height: 74)
                .background(.background, in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 4) {
                Text("Lumo").font(.title2.weight(.semibold))
                Text("\(style.shape.title) · \(style.color.hexLabel)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
    }

    private func shapeButton(_ shape: BotShape) -> some View {
        let selected = style.shape == shape
        return Button {
            style.shape = shape
        } label: {
            BotThumbnail(shape: shape, color: style.color)
                .frame(width: 45, height: 45)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(.quaternary.opacity(selected ? 0.7 : 0.3), in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 9).strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shape.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(shape.title)
    }

    private func colorButton(_ swatch: Swatch) -> some View {
        let selected = swatch.color == style.color
        return Button {
            style.color = swatch.color
        } label: {
            Circle()
                .fill(Color(nsColor: swatch.color.nsColor))
                .overlay { Circle().strokeBorder(.primary.opacity(0.08)) }
                .frame(width: 28, height: 28)
                .padding(4)
                .overlay {
                    if selected {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(swatch.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(swatch.title)
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: style.color.nsColor) },
            set: { color in
                if let custom = BotColor(nsColor: NSColor(color)) {
                    style.color = custom
                }
            }
        )
    }
}

private struct BotThumbnail: View {
    let shape: BotShape
    let color: BotColor

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 150
            let transform = CGAffineTransform(
                a: scale, b: 0, c: 0, d: -scale, tx: size.width / 2, ty: size.height / 2
            )
            context.fill(Path(shape.outline).applying(transform), with: .color(Color(nsColor: color.nsColor)))

            let ink = Color(nsColor: color.eyeColor)
            for x: CGFloat in [-21, 8] {
                let eye = Path(roundedRect: CGRect(x: x, y: -18.5, width: 13, height: 29), cornerRadius: 6.5)
                context.fill(eye.applying(transform), with: .color(ink))
            }
        }
        .accessibilityHidden(true)
    }
}
