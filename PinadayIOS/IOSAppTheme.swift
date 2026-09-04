import SwiftUI
import UIKit

enum AppTheme {
    struct Palette: Equatable {
        let kind: AppThemeKind
        let paper: Color
        let paperInset: Color
        let accent: Color
        let text: Color
        let secondaryText: Color
        let completedText: Color
        let separator: Color
        let controlBackground: Color
        let controlPressedBackground: Color
        let textUI: UIColor
        let secondaryTextUI: UIColor
        let completedTextUI: UIColor
        let accentUI: UIColor
        let codeBackgroundUI: UIColor

        static func == (lhs: Palette, rhs: Palette) -> Bool {
            lhs.kind == rhs.kind
        }
    }

    static let yellow = Palette(
        kind: .yellow,
        paper: Color(red: 1.0, green: 0.95, blue: 0.70),
        paperInset: Color(red: 1.0, green: 0.98, blue: 0.82),
        accent: Color(red: 0.16, green: 0.34, blue: 0.42),
        text: Color(red: 0.17, green: 0.14, blue: 0.10),
        secondaryText: Color(red: 0.42, green: 0.35, blue: 0.25),
        completedText: Color(red: 0.50, green: 0.46, blue: 0.38),
        separator: Color(red: 0.70, green: 0.56, blue: 0.28).opacity(0.35),
        controlBackground: Color.white.opacity(0.26),
        controlPressedBackground: Color.white.opacity(0.42),
        textUI: UIColor(red: 0.17, green: 0.14, blue: 0.10, alpha: 1),
        secondaryTextUI: UIColor(red: 0.42, green: 0.35, blue: 0.25, alpha: 1),
        completedTextUI: UIColor(red: 0.50, green: 0.46, blue: 0.38, alpha: 1),
        accentUI: UIColor(red: 0.16, green: 0.34, blue: 0.42, alpha: 1),
        codeBackgroundUI: UIColor(red: 1.0, green: 0.92, blue: 0.62, alpha: 0.72)
    )

    static let light = Palette(
        kind: .light,
        paper: Color(red: 0.96, green: 0.97, blue: 0.95),
        paperInset: Color(red: 1.0, green: 1.0, blue: 0.98),
        accent: Color(red: 0.13, green: 0.34, blue: 0.42),
        text: Color(red: 0.12, green: 0.13, blue: 0.12),
        secondaryText: Color(red: 0.38, green: 0.41, blue: 0.38),
        completedText: Color(red: 0.52, green: 0.55, blue: 0.52),
        separator: Color(red: 0.58, green: 0.62, blue: 0.58).opacity(0.34),
        controlBackground: Color.black.opacity(0.06),
        controlPressedBackground: Color.black.opacity(0.10),
        textUI: UIColor(red: 0.12, green: 0.13, blue: 0.12, alpha: 1),
        secondaryTextUI: UIColor(red: 0.38, green: 0.41, blue: 0.38, alpha: 1),
        completedTextUI: UIColor(red: 0.52, green: 0.55, blue: 0.52, alpha: 1),
        accentUI: UIColor(red: 0.13, green: 0.34, blue: 0.42, alpha: 1),
        codeBackgroundUI: UIColor(red: 0.88, green: 0.91, blue: 0.86, alpha: 0.86)
    )

    static let dark = Palette(
        kind: .dark,
        paper: Color(red: 0.11, green: 0.12, blue: 0.11),
        paperInset: Color(red: 0.16, green: 0.17, blue: 0.15),
        accent: Color(red: 0.46, green: 0.75, blue: 0.78),
        text: Color(red: 0.91, green: 0.90, blue: 0.86),
        secondaryText: Color(red: 0.67, green: 0.66, blue: 0.60),
        completedText: Color(red: 0.52, green: 0.53, blue: 0.50),
        separator: Color(red: 0.73, green: 0.72, blue: 0.62).opacity(0.20),
        controlBackground: Color.white.opacity(0.08),
        controlPressedBackground: Color.white.opacity(0.14),
        textUI: UIColor(red: 0.91, green: 0.90, blue: 0.86, alpha: 1),
        secondaryTextUI: UIColor(red: 0.67, green: 0.66, blue: 0.60, alpha: 1),
        completedTextUI: UIColor(red: 0.52, green: 0.53, blue: 0.50, alpha: 1),
        accentUI: UIColor(red: 0.46, green: 0.75, blue: 0.78, alpha: 1),
        codeBackgroundUI: UIColor(red: 0.23, green: 0.27, blue: 0.24, alpha: 0.95)
    )

    static func palette(for kind: AppThemeKind) -> Palette {
        switch kind {
        case .yellow: yellow
        case .light: light
        case .dark: dark
        }
    }
}

struct IOSHeaderButtonStyle: ButtonStyle {
    let palette: AppTheme.Palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(palette.accent)
            .frame(width: 40, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? palette.controlPressedBackground : .clear)
            )
            .contentShape(Rectangle())
    }
}
