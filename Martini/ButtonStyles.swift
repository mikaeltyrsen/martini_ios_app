import SwiftUI

struct MartiniBtn: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.martiniDefaultTextColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.martiniDefaultColor)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct MartiniBtnOutlined: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.martiniDefaultColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.martiniDefaultColor, lineWidth: 3)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct GlassIconButton<Label: View>: View {
    let size: CGFloat
    let glass: Glass
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    init(
        size: CGFloat = 44,
        glass: Glass = .regular.interactive(),
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.size = size
        self.glass = glass
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        // Ensure a reliable minimum hit target for glass buttons on iOS 26.
        .frame(minWidth: 44, minHeight: 44)
        // Expand hit testing beyond visible/opaque pixels.
        .contentShape(Rectangle())
        .glassEffect(glass, in: Circle())
    }
}
