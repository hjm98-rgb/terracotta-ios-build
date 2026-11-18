import SwiftUI

/// 陶瓦可视化规范：MC 味深色 + 陶土橙，等宽字体，硬描边卡片。
enum Theme {

    // 色彩
    static let background = Color(hex: 0x14110F)
    static let card = Color(hex: 0x1E1916)
    static let cardRaised = Color(hex: 0x272019)
    static let border = Color(hex: 0x3A2F28)
    static let accent = Color(hex: 0xD97A45)
    static let accentDim = Color(hex: 0x8A4E2C)
    static let success = Color(hex: 0x6FA96A)
    static let warning = Color(hex: 0xD9B245)
    static let danger = Color(hex: 0xC7564C)
    static let textPrimary = Color(hex: 0xEDE6DF)
    static let textSecondary = Color(hex: 0x9C8E82)
    static let textDim = Color(hex: 0x6A5E54)

    // 字体
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func title(_ size: CGFloat = 20) -> Font { mono(size, weight: .bold) }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - 通用组件

/// 硬边卡片：2px 描边，模拟像素风面板。
struct PixelCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Theme.border, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

/// 主按钮：陶土橙实心块，按下去有位移。
struct PixelButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(16, weight: .bold))
            .foregroundStyle(Color(hex: 0x1A120C))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(configuration.isPressed ? tint.opacity(0.75) : tint)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.black.opacity(0.55), lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .offset(y: configuration.isPressed ? 2 : 0)
    }
}

/// 次按钮：描边款。
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(15, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Theme.cardRaised)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Theme.border, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 顶部状态胶囊
struct StatusPill: View {
    var connected: Bool
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connected ? Theme.success : Theme.danger)
                .frame(width: 8, height: 8)
            Text(text)
                .font(Theme.mono(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 2).stroke(Theme.border, lineWidth: 1)
        )
    }
}

/// 小节标题
struct SectionLabel: View {
    var text: String

    var body: some View {
        Text(text)
            .font(Theme.mono(12, weight: .bold))
            .foregroundStyle(Theme.textDim)
            .textCase(.uppercase)
            .tracking(1.5)
    }
}
