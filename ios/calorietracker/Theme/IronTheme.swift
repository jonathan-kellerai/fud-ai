import SwiftUI
import UIKit

/// Iron & Blood. Every rendered color in the app comes from this file.
/// Alternate-icon gradients live here too so views do not carry hex literals.
enum IronTheme {
    static let cardRadius: CGFloat = 6
    /// iPhone SE's floating tab bar starts about 82pt from the bottom. Lists need
    /// at least that much trailing inset or the last row sits underneath it.
    static let floatingTabClearance: CGFloat = 88
    static let buttonRadius: CGFloat = 4
    static let ruleWidth: CGFloat = 3
    static let motionDuration: Double = 0.18
    static let grainOpacity: Double = 0.04

    /// Warm iron black. Spec #0B0A09.
    static let canvas = Color(hex: Hex.canvas)
    /// Cards. Spec #171513.
    static let surface = Color(hex: Hex.surface)
    /// Sheets, pressed cards, inputs. Spec #221F1B.
    static let surfaceRaised = Color(hex: Hex.surfaceRaised)
    /// 1 px borders. Spec #3A342D.
    static let hairline = Color(hex: Hex.hairline)
    /// Bone white. Spec #EDE6D6.
    static let textPrimary = Color(hex: Hex.textPrimary)
    /// Faded bone. Spec #A89F8C.
    static let textSecondary = Color(hex: Hex.textSecondary)
    /// Disabled, placeholders, inactive tabs.
    /// Lifted from spec #6E665A to #8C867D so small labels clear 4.5:1 on surfaceRaised.
    static let textTertiary = Color(hex: Hex.textTertiary)
    /// Primary accent fill. Spec #B3121B. Not used as small text (2.84:1 on canvas).
    static let blood = Color(hex: Hex.blood)
    /// Pressed and destructive fill. Spec #8A0E15.
    static let bloodPressed = Color(hex: Hex.bloodPressed)
    /// Red as text or a thin stroke.
    /// Lifted from spec #E0393E to #E2464A so body text clears 4.5:1 on surface.
    static let bloodText = Color(hex: Hex.bloodText)
    /// PRs, streaks, ready. Spec #C9A227. Unchanged; already passes.
    static let brass = Color(hex: Hex.brass)
    /// Warnings, reduction week, missed steps.
    /// Lifted from spec #C4561D to #C9642F so body text clears 4.5:1 on surface.
    static let rust = Color(hex: Hex.rust)
    /// Completed. Spec #7F8F4E.
    static let olive = Color(hex: Hex.olive)
    /// Neutral chips and rest-day cards. Spec #4A4640. Fill only.
    static let concrete = Color(hex: Hex.concrete)

    static var motion: Animation { .easeOut(duration: motionDuration) }

    /// Heavy headline for CTAs and heavy labels: 17 pt at the default size, scaling with Dynamic Type.
    static let heavyHeadline: Font = .headline.weight(.heavy)

    enum Hex {
        static let canvas: UInt = 0x0B0A09
        static let surface: UInt = 0x171513
        static let surfaceRaised: UInt = 0x221F1B
        static let hairline: UInt = 0x3A342D
        static let textPrimary: UInt = 0xEDE6D6
        static let textSecondary: UInt = 0xA89F8C
        static let textTertiary: UInt = 0x8C867D
        static let blood: UInt = 0xB3121B
        static let bloodPressed: UInt = 0x8A0E15
        static let bloodText: UInt = 0xE2464A
        static let brass: UInt = 0xC9A227
        static let rust: UInt = 0xC9642F
        static let olive: UInt = 0x7F8F4E
        static let concrete: UInt = 0x4A4640
    }

    static func alternateIconStartHex(_ theme: AppThemeColor) -> UInt {
        switch theme {
        case .fudPink: return 0xFF375F
        case .red: return 0xFF3B30
        case .orange: return 0xFF9500
        case .green: return 0x34C759
        case .mint: return 0x00C7BE
        case .teal: return 0x30B0C7
        case .blue: return 0x0A84FF
        case .purple: return 0xAF52DE
        case .yellow: return 0xFFCC00
        case .coral: return 0xFF7F50
        case .roseGold: return 0xC9807C
        case .mochaBrown: return 0xA2845E
        case .indigo: return 0x5856D6
        case .lavender: return 0xB57EDC
        case .skyCyan: return 0x32ADE6
        case .graphite: return 0x8E8E93
        case .babyPink: return 0xFF8FAB
        case .lime: return 0xA0D911
        }
    }

    static func alternateIconEndHex(_ theme: AppThemeColor) -> UInt {
        switch theme {
        case .fudPink: return 0xFF6B8A
        case .red: return 0xFF6961
        case .orange: return 0xFFB340
        case .green: return 0x62D46F
        case .mint: return 0x66D4CF
        case .teal: return 0x64D2FF
        case .blue: return 0x5EAEFF
        case .purple: return 0xBF5AF2
        case .yellow: return 0xFFD60A
        case .coral: return 0xFFA382
        case .roseGold: return 0xE8B4B0
        case .mochaBrown: return 0xC9A57E
        case .indigo: return 0x7D7AFF
        case .lavender: return 0xD0A9F5
        case .skyCyan: return 0x70CFFF
        case .graphite: return 0xB8B8BE
        case .babyPink: return 0xFFB3C6
        case .lime: return 0xC3E956
        }
    }

    /// WCAG relative-luminance contrast. Used by tests and the PR table.
    static func contrastRatio(foreground: UInt, on background: UInt) -> Double {
        let lighter = max(relativeLuminance(foreground), relativeLuminance(background))
        let darker = min(relativeLuminance(foreground), relativeLuminance(background))
        return (lighter + 0.05) / (darker + 0.05)
    }

    static func relativeLuminance(_ hex: UInt) -> Double {
        func channel(_ value: Double) -> Double {
            let unit = value / 255
            if unit <= 0.04045 { return unit / 12.92 }
            return pow((unit + 0.055) / 1.055, 2.4)
        }
        let red = channel(Double((hex >> 16) & 255))
        let green = channel(Double((hex >> 8) & 255))
        let blue = channel(Double(hex & 255))
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    static func applyChrome() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(canvas)
        tab.shadowColor = UIColor(hairline)
        let inactive = UIColor(textTertiary)
        let active = UIColor(bloodText)
        for layout in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            layout.normal.iconColor = inactive
            layout.normal.titleTextAttributes = [.foregroundColor: inactive]
            layout.selected.iconColor = active
            layout.selected.titleTextAttributes = [.foregroundColor: active]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        let canvasColor = UIColor(canvas)
        UITableView.appearance().backgroundColor = canvasColor
        UICollectionView.appearance().backgroundColor = canvasColor
        UITableView.appearance().separatorColor = UIColor(hairline)

        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(canvas)
        navigation.shadowColor = UIColor(hairline)
        let titleFont = UIFont.systemFont(ofSize: 17, weight: .heavy, width: .condensed)
        let titleColor = UIColor(textPrimary)
        navigation.titleTextAttributes = [
            .foregroundColor: titleColor,
            .font: titleFont
        ]
        navigation.largeTitleTextAttributes = [
            .foregroundColor: titleColor,
            .font: UIFont.systemFont(ofSize: 34, weight: .black, width: .condensed)
        ]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
    }
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            red: Double((hex >> 16) & 255) / 255,
            green: Double((hex >> 8) & 255) / 255,
            blue: Double(hex & 255) / 255,
            opacity: opacity
        )
    }
}

extension View {
    /// Keeps the last row of a settings list above the floating tab bar.
    func settingsFloatingTabClearance() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: IronTheme.floatingTabClearance)
                .accessibilityHidden(true)
        }
    }

    /// Lets a short label use a second line and scale slightly instead of hyphenating mid-word.
    func avoidsMidWordBreak() -> some View {
        lineLimit(2)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
    }
}

/// Text that may scale or wrap onto a second line, but does not hyphenate inside a word.
/// A single word ("Acknowledgements") always stays on one line: it is laid out at its ideal width
/// at AX1, then xxxLarge, xLarge and large, and the first size that fits the row wins. Only if none
/// fits does it fall back to scaling down at large. `minimumScaleFactor` alone is unreliable in a
/// List row Label, where the word was truncated instead of shrunk.
struct UnbrokenText: View {
    private let string: String
    private let isSingleWord: Bool

    init(_ string: String) {
        self.string = string
        isSingleWord = Self.isSingleWord(string)
    }

    init(_ resource: LocalizedStringResource) {
        let string = String(localized: resource)
        self.string = string
        isSingleWord = Self.isSingleWord(string)
    }

    var body: some View {
        if isSingleWord {
            ViewThatFits(in: .horizontal) {
                singleLine(cappedAt: .accessibility1)
                singleLine(cappedAt: .xxxLarge)
                singleLine(cappedAt: .xLarge)
                singleLine(cappedAt: .large)
                Text(verbatim: string)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .allowsTightening(true)
                    .dynamicTypeSize(...DynamicTypeSize.large)
            }
        } else {
            Text(verbatim: string)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
        }
    }

    /// The word at its full ideal width, so ViewThatFits rejects it rather than letting it truncate.
    private func singleLine(cappedAt size: DynamicTypeSize) -> some View {
        Text(verbatim: string)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .dynamicTypeSize(...size)
    }

    static func isSingleWord(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains { $0.isWhitespace }
    }
}

struct AdaptiveLabelValue<Label: View, Value: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Rows whose value is a control (a Toggle) use `.center`, so the switch stays level with the label.
    var alignment: VerticalAlignment = .firstTextBaseline
    @ViewBuilder var label: () -> Label
    @ViewBuilder var value: () -> Value

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                label()
                value()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: alignment, spacing: 12) {
                label()
                Spacer(minLength: 8)
                value()
            }
        }
    }
}

struct IronSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .heavy))
            .fontWidth(.condensed)
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(IronTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct IronCardModifier: ViewModifier {
    var fill: Color = IronTheme.surface
    var showsRule: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: IronTheme.cardRadius, style: .continuous)
        content
            .background(fill)
            .overlay(alignment: .leading) {
                if showsRule {
                    Rectangle()
                        .fill(IronTheme.blood)
                        .frame(width: IronTheme.ruleWidth)
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(IronTheme.hairline, lineWidth: 1)
            }
    }
}

struct IronCompactButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .heavy))
            .fontWidth(.condensed)
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(IronTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                configuration.isPressed ? IronTheme.bloodPressed : IronTheme.blood,
                in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
            )
            .animation(reduceMotion ? nil : IronTheme.motion, value: configuration.isPressed)
    }
}

struct IronPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Grows with Dynamic Type so taller labels keep their breathing room.
    @ScaledMetric(relativeTo: .headline) private var verticalPadding: CGFloat = 14
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(IronTheme.heavyHeadline)
            .fontWidth(.condensed)
            .tracking(1.0)
            .textCase(.uppercase)
            .multilineTextAlignment(.center)
            .foregroundStyle(IronTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, verticalPadding)
            .background(
                enabled ? (configuration.isPressed ? IronTheme.bloodPressed : IronTheme.blood) : IronTheme.concrete,
                in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
            )
            .animation(reduceMotion ? nil : IronTheme.motion, value: configuration.isPressed)
    }
}

struct IronGrainOverlay: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if !reduceTransparency {
            Image(uiImage: IronGrainTile.image)
                .resizable(resizingMode: .tile)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .opacity(IronTheme.grainOpacity)
        }
    }
}

enum IronGrainTile {
    private static let tileSide = 128
    private static let speckCount = 1_600

    static let image: UIImage = {
        let rendered = renderGrain()
        guard rendered.size.width > 0, rendered.size.height > 0 else {
            return plainTile()
        }
        return rendered
    }()

    private static func renderGrain() -> UIImage {
        let side = tileSide
        guard side > 0 else { return plainTile() }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { context in
            UIColor(IronTheme.canvas).setFill()
            context.fill(CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)))
            for index in 0..<speckCount {
                guard let origin = speckOrigin(index: index, side: side) else { continue }
                UIColor(white: speckLuma(index: index), alpha: speckAlpha(index: index)).setFill()
                context.fill(CGRect(x: origin.x, y: origin.y, width: 1, height: 1))
            }
        }
    }

    private static func speckOrigin(index: Int, side: Int) -> CGPoint? {
        guard side > 0 else { return nil }
        let x = mix(index, salt: 1) % side
        let y = mix(index, salt: 7) % side
        guard x >= 0, y >= 0 else { return nil }
        return CGPoint(x: x, y: y)
    }

    private static func speckAlpha(index: Int) -> CGFloat {
        let mixed = mix(index, salt: 13)
        guard mixed >= 0 else { return 0.2 }
        let byte = 40 + (mixed % 180)
        guard (0...255).contains(byte) else { return 0.2 }
        return CGFloat(byte) / 255
    }

    private static func speckLuma(index: Int) -> CGFloat {
        let mixed = mix(index, salt: 3)
        guard mixed >= 0 else { return 1 }
        return mixed % 2 == 0 ? 1 : 0
    }

    /// Wrapping hash. `Int32(_:)` traps when the product does not fit, which
    /// happens from speck index 6 (`6 * 374761393` is past Int32.max).
    static func mix(_ value: Int, salt: Int) -> Int {
        var mixed = UInt32(truncatingIfNeeded: value) &* 374_761_393
        mixed &+= UInt32(truncatingIfNeeded: salt) &* 668_265_263
        mixed = (mixed ^ (mixed >> 13)) &* 1_274_126_177
        return Int(mixed & 0x7fff_ffff)
    }

    private static func plainTile() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { context in
            UIColor(IronTheme.canvas).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }
}

extension View {
    func ironCard(fill: Color = IronTheme.surface, rule: Bool = false) -> some View {
        modifier(IronCardModifier(fill: fill, showsRule: rule))
    }
}
