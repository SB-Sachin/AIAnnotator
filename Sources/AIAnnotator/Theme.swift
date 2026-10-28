import AnnotatorCore
import AppKit
import SwiftUI

/// Colors, type and controls shared across the app. The palette comes from the app icon:
/// indigo with a gold accent on warm, quiet neutrals.
enum Theme {
    static let brand = Color(hex: 0x5B4BD6)
    static let brandDeep = Color(hex: 0x3A2E9C)
    static let gold = Color(hex: 0xFFB547)
    static let brandGradient = LinearGradient(colors: [Color(hex: 0x7B6CF0), Color(hex: 0x4F3FCC)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)

    static let canvas = Color(nsColor: dynamic(light: 0xF8F7F4, dark: 0x1B1A1F))
    static let card = Color(nsColor: dynamic(light: 0xFFFFFF, dark: 0x26252C))
    static let well = Color(nsColor: dynamic(light: 0xEFEDE8, dark: 0x141317))
    static let hairline = Color.primary.opacity(0.08)
    static let pdfBackground = dynamic(light: 0xEDEBE6, dark: 0x141317)

    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension View {
    /// A raised surface: card fill, hairline border and a soft shadow.
    func card(_ radius: CGFloat = 16, shadow: Bool = true) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.card)
                .shadow(color: .black.opacity(shadow ? 0.06 : 0), radius: 12, y: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, large: large)
    }

    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        let large: Bool
        @Environment(\.isEnabled) private var enabled
        @ViewState private var hover = false

        var body: some View {
            configuration.label
                .font(.system(size: large ? 14 : 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, large ? 22 : 16).padding(.vertical, large ? 11 : 8)
                .background(Theme.brandGradient, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
                .shadow(color: Theme.brand.opacity(enabled ? (hover ? 0.45 : 0.3) : 0), radius: hover ? 12 : 8, y: 4)
                .brightness(hover && enabled ? 0.05 : 0)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(enabled ? 1 : 0.45)
                .animation(.easeOut(duration: 0.15), value: hover)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
                .onHover { hover = $0 }
        }
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        @ViewState private var hover = false

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.primary.opacity(configuration.isPressed ? 0.12 : hover ? 0.08 : 0.05), in: Capsule())
                .opacity(enabled ? 1 : 0.4)
                .onHover { hover = $0 }
                .animation(.easeOut(duration: 0.12), value: hover)
        }
    }
}

/// A selectable tile used in the run sheet.
struct ChoiceCard<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: Content
    @ViewState private var hover = false

    var body: some View {
        Button(action: action) {
            content
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(selected ? Theme.brand.opacity(0.09) : Theme.card)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? Theme.brand : hover ? Color.primary.opacity(0.18) : Theme.hairline,
                                      lineWidth: selected ? 1.5 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: selected)
    }
}

/// A capsule segmented control.
struct PillPicker<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let on = option.value == selection
                Button { withAnimation(.snappy(duration: 0.2)) { selection = option.value } } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: on ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(on ? Color.primary : Color.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background {
                            if on {
                                Capsule().fill(Theme.card).shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

struct BrandMark: View {
    var size: CGFloat = 28

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

struct CategoryDot: View {
    let color: NSColor
    var size: CGFloat = 8

    var body: some View {
        Circle().fill(Color(nsColor: color)).frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.black.opacity(0.08)))
    }
}

extension RunMode {
    var symbol: String {
        switch self {
        case .notes: return "note.text"
        case .annotations: return "highlighter"
        case .both: return "sparkles"
        }
    }
    var blurb: String {
        switch self {
        case .notes: return "Study notes in a template"
        case .annotations: return "Highlights on the pages"
        case .both: return "Notes and highlights"
        }
    }
}

/// Lays children out left to right, wrapping onto new lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            for (index, x) in row.items {
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified)
            }
        }
    }

    private struct Row {
        var items: [(index: Int, x: CGFloat)] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if rows[rows.count - 1].width > 0, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            let x = row.width > 0 ? row.width + spacing : 0
            row.items.append((i, x))
            row.width = x + size.width
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
