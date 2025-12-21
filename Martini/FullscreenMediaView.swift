import SwiftUI

struct FullscreenMediaView: View {
    let url: URL?
    let isVideo: Bool
    let aspectRatio: CGFloat
    let title: String?
    let frameNumberLabel: String?
    let namespace: Namespace.ID
    let heroID: String
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showChrome: Bool = false
    @State private var backgroundOpacity: Double = 0
    @State private var mediaOpacity: Double = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color.black
                    .opacity(backgroundOpacity)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 12) {
                    Spacer()

                    FrameLayout.HeroMediaView(
                        url: url,
                        isVideo: isVideo,
                        aspectRatio: aspectRatio,
                        contentMode: .fit,
                        cornerRadius: 0,
                        namespace: namespace,
                        heroID: heroID,
                        frameNumberLabel: frameNumberLabel,
                        placeholder: fallbackPlaceholder,
                        imageShouldFill: false,
                        isSource: false,
                        useMatchedGeometry: false
                    )
                    .frame(maxWidth: proxy.size.width * 0.98)
                    .opacity(mediaOpacity)
                    .animation(.easeInOut(duration: 0.25), value: mediaOpacity)

                    metadata
                        .opacity(showChrome ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: showChrome)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showChrome.toggle()
                    }
                }

                if showChrome {
                    topToolbar(topPadding: proxy.safeAreaInsets.top)
                        .padding(.horizontal, 16)
                        .transition(.opacity)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.25)) {
                backgroundOpacity = 1
                mediaOpacity = 1
            }
        }
        .onDisappear {
            backgroundOpacity = 0
            mediaOpacity = 0
        }
    }

    private func topToolbar(topPadding: CGFloat) -> some View {
        HStack {
            Button {
                onDismiss()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .accessibilityLabel("Close fullscreen")

            Spacer()
        }
        .padding(.top, max(20, topPadding + 8))
    }

    @ViewBuilder
    private var metadata: some View {
        if let title, !title.isEmpty {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
        } else if let frameNumberLabel {
            Text(frameNumberLabel)
                .font(.headline)
                .foregroundStyle(.white)
        } else {
            EmptyView()
        }
    }

    private var fallbackPlaceholder: AnyView {
        AnyView(
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundStyle(.white.opacity(0.7))
                if let frameNumberLabel {
                    Text(frameNumberLabel)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        )
    }
}
