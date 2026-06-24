import SwiftUI

enum AppTheme {
    static let paper = Color(red: 1.0, green: 0.95, blue: 0.70)
    static let paperInset = Color(red: 1.0, green: 0.98, blue: 0.82)
    static let accent = Color(red: 0.16, green: 0.34, blue: 0.42)
    static let text = Color(red: 0.17, green: 0.14, blue: 0.10)
    static let secondaryText = Color(red: 0.42, green: 0.35, blue: 0.25)
    static let completedText = Color(red: 0.50, green: 0.46, blue: 0.38)
    static let separator = Color(red: 0.70, green: 0.56, blue: 0.28).opacity(0.35)
    static let controlBackground = Color.white.opacity(0.26)
    static let controlPressedBackground = Color.white.opacity(0.42)
}

struct StickyIconButtonStyle: ButtonStyle {
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isActive ? AppTheme.accent : AppTheme.text)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? AppTheme.controlPressedBackground : backgroundColor)
            )
    }

    private var backgroundColor: Color {
        isActive ? AppTheme.accent.opacity(0.16) : AppTheme.controlBackground
    }
}

struct StickyTextButtonStyle: ButtonStyle {
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isActive ? AppTheme.accent : AppTheme.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? AppTheme.controlPressedBackground : AppTheme.controlBackground)
            )
    }
}

