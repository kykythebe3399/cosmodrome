import AppKit
import Core
import SwiftUI

// MARK: - Spacing

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Corner Radii

enum Radius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let lg: CGFloat = 8
    static let xl: CGFloat = 12
}

// MARK: - Typography

enum Typo {
    static let caption = Font.system(size: 9)
    static let captionMono = Font.system(size: 9, design: .monospaced)
    static let footnote = Font.system(size: 10)
    static let footnoteMedium = Font.system(size: 10, weight: .medium)
    static let footnoteMono = Font.system(size: 10, design: .monospaced)
    static let body = Font.system(size: 11)
    static let bodyMedium = Font.system(size: 11, weight: .medium)
    static let callout = Font.system(size: 12)
    static let subheading = Font.system(size: 13)
    static let subheadingMedium = Font.system(size: 13, weight: .medium)
    static let title = Font.system(size: 14, weight: .semibold)
    static let largeTitle = Font.system(size: 15, weight: .semibold)
}

// MARK: - Colors (Semantic, appearance-adaptive)

/// Helper to create an NSColor that automatically switches between dark and light variants
/// based on the current NSAppearance (set by window.appearance).
private func adaptive(dark: NSColor, light: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? dark : light
    }))
}

enum DS {
    // Backgrounds
    static let bgPrimary = adaptive(
        dark: NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1),
        light: NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
    )
    static let bgSidebar = adaptive(
        dark: NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1),
        light: NSColor(red: 0.93, green: 0.93, blue: 0.94, alpha: 1)
    )
    static let bgElevated = adaptive(
        dark: NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1),
        light: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)
    )
    static let bgSurface = adaptive(
        dark: NSColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 1),
        light: NSColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1)
    )

    // Interactive backgrounds
    static let bgHover = adaptive(
        dark: NSColor.white.withAlphaComponent(0.06),
        light: NSColor.black.withAlphaComponent(0.04)
    )
    static let bgSelected = adaptive(
        dark: NSColor.white.withAlphaComponent(0.10),
        light: NSColor.black.withAlphaComponent(0.08)
    )
    static let bgPressed = adaptive(
        dark: NSColor.white.withAlphaComponent(0.14),
        light: NSColor.black.withAlphaComponent(0.12)
    )

    // Text
    static let textPrimary = adaptive(
        dark: NSColor.white.withAlphaComponent(0.92),
        light: NSColor.black.withAlphaComponent(0.88)
    )
    static let textSecondary = adaptive(
        dark: NSColor.white.withAlphaComponent(0.60),
        light: NSColor.black.withAlphaComponent(0.55)
    )
    static let textTertiary = adaptive(
        dark: NSColor.white.withAlphaComponent(0.40),
        light: NSColor.black.withAlphaComponent(0.35)
    )
    static let textInverse = adaptive(
        dark: NSColor.black,
        light: NSColor.white
    )

    // Borders
    static let borderSubtle = adaptive(
        dark: NSColor.white.withAlphaComponent(0.06),
        light: NSColor.black.withAlphaComponent(0.06)
    )
    static let borderMedium = adaptive(
        dark: NSColor.white.withAlphaComponent(0.12),
        light: NSColor.black.withAlphaComponent(0.10)
    )
    static let borderStrong = adaptive(
        dark: NSColor.white.withAlphaComponent(0.20),
        light: NSColor.black.withAlphaComponent(0.18)
    )
    static let borderFocus = Color.accentColor.opacity(0.6)

    // Agent state colors (same in both modes — they're already high-contrast)
    static let stateWorking = Color(red: 0.30, green: 0.85, blue: 0.45)
    static let stateNeedsInput = Color(red: 1.0, green: 0.82, blue: 0.28)
    static let stateError = Color(red: 1.0, green: 0.38, blue: 0.38)
    static let stateInactive = adaptive(
        dark: NSColor.white.withAlphaComponent(0.30),
        light: NSColor.black.withAlphaComponent(0.25)
    )

    // Accent
    static let accent = Color.accentColor
    static let accentSubtle = Color.accentColor.opacity(0.15)

    // Shadows
    static let shadowLight = Color.black.opacity(0.20)
    static let shadowMedium = Color.black.opacity(0.35)
    static let shadowHeavy = Color.black.opacity(0.50)

    // Dismiss overlay
    static let overlay = Color.black.opacity(0.25)

    static func stateColor(for state: Core.AgentState) -> Color {
        switch state {
        case .working: return stateWorking
        case .needsInput: return stateNeedsInput
        case .error: return stateError
        case .inactive: return stateInactive
        }
    }
}

// MARK: - Animations

enum Anim {
    static let quick = Animation.easeInOut(duration: 0.15)
    static let normal = Animation.easeInOut(duration: 0.25)
    static let slow = Animation.easeInOut(duration: 0.35)
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.8)
}

// MARK: - Reusable View Modifiers

struct HoverEffect: ViewModifier {
    @State private var isHovered = false
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? DS.bgHover : Color.clear)
                    .animation(Anim.quick, value: isHovered)
            )
            .onHover { isHovered = $0 }
    }
}

extension View {
    func hoverHighlight(radius: CGFloat = Radius.sm) -> some View {
        modifier(HoverEffect(cornerRadius: radius))
    }
}
