import SwiftUI

struct MartiniAlertAction: Identifiable {
    enum Style {
        case primary
        case secondary
    }

    let id = UUID()
    let title: String
    let style: Style
    let role: ButtonRole?
    let tint: Color?
    let action: () -> Void

    init(
        title: String,
        style: Style = .secondary,
        role: ButtonRole? = nil,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.role = role
        self.tint = tint
        self.action = action
    }
}

struct MartiniAlertModal: View {
    @Binding var isPresented: Bool
    let iconName: String?
    let iconColor: Color
    let title: String
    let message: String
    let actions: [MartiniAlertAction]

    var body: some View {
        if isPresented {
            GeometryReader { proxy in
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: isPresented)

                    modalCard(maxWidth: min(400, proxy.size.width * 0.9))
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isPresented)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func modalCard(maxWidth: CGFloat) -> some View {
        VStack(spacing: 16) {
            if let iconName {
                Image(systemName: iconName)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                ForEach(actions) { action in
                    actionButton(for: action)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: maxWidth)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
    }

    @ViewBuilder
    private func actionButton(for action: MartiniAlertAction) -> some View {
        let tint = action.tint ?? (action.style == .primary ? .martiniDefaultColor : .secondary)

        Group {
            if action.style == .primary {
                Button(action.title, role: action.role, action: action.action)
                    .buttonStyle(.borderedProminent)
            } else {
                Button(action.title, role: action.role, action: action.action)
                    .buttonStyle(.bordered)
            }
        }
        .tint(tint)
        .frame(maxWidth: .infinity)
    }
}
