import AppKit
import SwiftUI

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
        let textNS: NSColor
        let secondaryTextNS: NSColor
        let completedTextNS: NSColor
        let accentNS: NSColor
        let codeBackgroundNS: NSColor
        let strikethroughNS: NSColor
        let checkboxUncheckedNS: NSColor
        let checkboxBorderNS: NSColor
        let checkboxCheckmarkNS: NSColor

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
        textNS: NSColor(calibratedRed: 0.17, green: 0.14, blue: 0.10, alpha: 1),
        secondaryTextNS: NSColor(calibratedRed: 0.42, green: 0.35, blue: 0.25, alpha: 1),
        completedTextNS: NSColor(calibratedRed: 0.50, green: 0.46, blue: 0.38, alpha: 1),
        accentNS: NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.42, alpha: 1),
        codeBackgroundNS: NSColor(calibratedRed: 1.0, green: 0.92, blue: 0.62, alpha: 0.72),
        strikethroughNS: NSColor(calibratedRed: 0.43, green: 0.37, blue: 0.30, alpha: 1),
        checkboxUncheckedNS: NSColor(calibratedWhite: 1.0, alpha: 0.82),
        checkboxBorderNS: NSColor(calibratedRed: 0.40, green: 0.35, blue: 0.20, alpha: 0.56),
        checkboxCheckmarkNS: .white
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
        textNS: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.12, alpha: 1),
        secondaryTextNS: NSColor(calibratedRed: 0.38, green: 0.41, blue: 0.38, alpha: 1),
        completedTextNS: NSColor(calibratedRed: 0.52, green: 0.55, blue: 0.52, alpha: 1),
        accentNS: NSColor(calibratedRed: 0.13, green: 0.34, blue: 0.42, alpha: 1),
        codeBackgroundNS: NSColor(calibratedRed: 0.88, green: 0.91, blue: 0.86, alpha: 0.86),
        strikethroughNS: NSColor(calibratedRed: 0.42, green: 0.45, blue: 0.42, alpha: 1),
        checkboxUncheckedNS: NSColor(calibratedWhite: 1.0, alpha: 0.9),
        checkboxBorderNS: NSColor(calibratedRed: 0.45, green: 0.48, blue: 0.45, alpha: 0.68),
        checkboxCheckmarkNS: .white
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
        textNS: NSColor(calibratedRed: 0.91, green: 0.90, blue: 0.86, alpha: 1),
        secondaryTextNS: NSColor(calibratedRed: 0.67, green: 0.66, blue: 0.60, alpha: 1),
        completedTextNS: NSColor(calibratedRed: 0.52, green: 0.53, blue: 0.50, alpha: 1),
        accentNS: NSColor(calibratedRed: 0.46, green: 0.75, blue: 0.78, alpha: 1),
        codeBackgroundNS: NSColor(calibratedRed: 0.23, green: 0.27, blue: 0.24, alpha: 0.95),
        strikethroughNS: NSColor(calibratedRed: 0.58, green: 0.59, blue: 0.54, alpha: 1),
        checkboxUncheckedNS: NSColor(calibratedWhite: 0.08, alpha: 0.88),
        checkboxBorderNS: NSColor(calibratedRed: 0.72, green: 0.72, blue: 0.66, alpha: 0.70),
        checkboxCheckmarkNS: .white
    )

    static let paper = yellow.paper
    static let paperInset = yellow.paperInset
    static let accent = yellow.accent
    static let text = yellow.text
    static let secondaryText = yellow.secondaryText
    static let completedText = yellow.completedText
    static let separator = yellow.separator
    static let controlBackground = yellow.controlBackground
    static let controlPressedBackground = yellow.controlPressedBackground

    static func palette(for kind: AppThemeKind) -> Palette {
        switch kind {
        case .yellow:
            return yellow
        case .light:
            return light
        case .dark:
            return dark
        }
    }
}

struct StickyIconButtonStyle: ButtonStyle {
    var isActive: Bool = false
    var palette: AppTheme.Palette = AppTheme.yellow

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isActive ? palette.accent : palette.text)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? palette.controlPressedBackground : backgroundColor)
            )
    }

    private var backgroundColor: Color {
        isActive ? palette.accent.opacity(0.16) : palette.controlBackground
    }
}

struct StickyTextButtonStyle: ButtonStyle {
    var isActive: Bool = false
    var palette: AppTheme.Palette = AppTheme.yellow

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isActive ? palette.accent : palette.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? palette.controlPressedBackground : palette.controlBackground)
            )
    }
}
