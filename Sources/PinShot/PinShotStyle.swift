import SwiftUI

enum PinShotPalette {
    static let selectionBlue = Color(red: 0.26, green: 0.58, blue: 0.98)
    static let softBlue = Color(red: 0.88, green: 0.94, blue: 1.0)
    static let warmBackgroundTop = Color(red: 0.97, green: 0.98, blue: 1.0)
    static let warmBackgroundBottom = Color(red: 0.93, green: 0.95, blue: 0.99)
    static let border = Color.white.opacity(0.58)
    static let shadow = Color.black.opacity(0.14)
    static let mutedForeground = Color.primary.opacity(0.72)
}

struct PinShotGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(PinShotPalette.border, lineWidth: 1)
            }
            .shadow(color: PinShotPalette.shadow, radius: 14, y: 8)
    }
}

extension View {
    func pinShotGlassCard(cornerRadius: CGFloat = 18, padding: CGFloat = 14) -> some View {
        modifier(PinShotGlassCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

struct PinToolbarButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: isActive ? .semibold : .medium, design: .rounded))
            .foregroundStyle(isActive ? PinShotPalette.selectionBlue : PinShotPalette.mutedForeground)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isActive ? PinShotPalette.selectionBlue.opacity(configuration.isPressed ? 0.18 : 0.14) : Color.white.opacity(configuration.isPressed ? 0.2 : 0.001))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isActive ? PinShotPalette.selectionBlue.opacity(0.28) : Color.clear, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

enum PinCapsuleProminence {
    case primary
    case secondary
    case subtle
}

struct PinCapsuleButtonStyle: ButtonStyle {
    let prominence: PinCapsuleProminence

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(background(configuration: configuration))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch prominence {
        case .primary:
            return .white
        case .secondary:
            return .primary.opacity(0.82)
        case .subtle:
            return PinShotPalette.selectionBlue
        }
    }

    private var borderColor: Color {
        switch prominence {
        case .primary:
            return PinShotPalette.selectionBlue.opacity(0.18)
        case .secondary:
            return Color.white.opacity(0.52)
        case .subtle:
            return PinShotPalette.selectionBlue.opacity(0.22)
        }
    }

    private var borderWidth: CGFloat {
        prominence == .primary ? 0 : 1
    }

    @ViewBuilder
    private func background(configuration: Configuration) -> some View {
        switch prominence {
        case .primary:
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            PinShotPalette.selectionBlue.opacity(configuration.isPressed ? 0.84 : 0.94),
                            PinShotPalette.selectionBlue.opacity(configuration.isPressed ? 0.72 : 0.84)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .secondary:
            Capsule(style: .continuous)
                .fill(Color.white.opacity(configuration.isPressed ? 0.32 : 0.22))
        case .subtle:
            Capsule(style: .continuous)
                .fill(PinShotPalette.softBlue.opacity(configuration.isPressed ? 0.72 : 0.96))
        }
    }
}

struct PinSidebarActionButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .foregroundStyle(isPrimary ? Color.white : Color.primary.opacity(0.82))
            .background(background(configuration: configuration))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isPrimary ? Color.clear : Color.white.opacity(0.54), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    @ViewBuilder
    private func background(configuration: Configuration) -> some View {
        if isPrimary {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            PinShotPalette.selectionBlue.opacity(configuration.isPressed ? 0.82 : 0.94),
                            Color(red: 0.18, green: 0.44, blue: 0.92).opacity(configuration.isPressed ? 0.76 : 0.88)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(configuration.isPressed ? 0.3 : 0.18))
        }
    }
}
