//
//  Uiplayground.swift
//  Martini
//
//  Created by Mikael Tyrsen on 11/29/25.
//

import SwiftUI

struct Uiplayground: View {
    private struct MediaThumbnail: Identifiable {
        let id = UUID()
        let title: String
        let media: MediaItem
        let config: MediaViewerConfig
        let thumbnailURL: URL
    }

    private let silentLoopConfig = MediaViewerConfig(
        showsVideoControls: false,
        showsPlayButtonOverlay: false,
        autoplay: true,
        loop: true,
        startMuted: true,
        audioEnabled: false
    )

    private let normalPlaybackConfig = MediaViewerConfig(
        showsVideoControls: true,
        autoplay: false,
        loop: false,
        startMuted: false,
        audioEnabled: true
    )

    private var thumbnails: [MediaThumbnail] {
        [
            MediaThumbnail(
                title: "Storyboard",
                media: .imageURL(URL(string: "https://picsum.photos/id/1025/1200/800")!),
                config: .default,
                thumbnailURL: URL(string: "https://picsum.photos/id/1025/400/300")!
            ),
            MediaThumbnail(
                title: "Silent Loop Preview",
                media: .videoURL(URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!),
                config: silentLoopConfig,
                thumbnailURL: URL(string: "https://picsum.photos/id/1040/400/300")!
            ),
            MediaThumbnail(
                title: "Playback + Sound",
                media: .videoURL(URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4")!),
                config: normalPlaybackConfig,
                thumbnailURL: URL(string: "https://picsum.photos/id/1062/400/300")!
            )
        ]
    }

    @State private var selectedMedia: MediaThumbnail?
    @State private var isViewerPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                    ForEach(thumbnails) { item in
                        Button {
                            selectedMedia = item
                            isViewerPresented = true
                        } label: {
                            VStack(spacing: 8) {
                                AsyncImage(url: item.thumbnailURL) { phase in
                                    switch phase {
                                    case .empty:
                                        MartiniLoader()
                                            .frame(maxWidth: .infinity, maxHeight: 100)
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(height: 100)
                                            .clipped()
                                            .overlay(alignment: .bottomTrailing) {
                                                if item.media.isVideo {
                                                    Image(systemName: "play.fill")
                                                        .font(.system(size: 12, weight: .bold))
                                                        .foregroundStyle(.white)
                                                        .padding(6)
                                                        .background(Circle().fill(.black.opacity(0.6)))
                                                        .padding(6)
                                                }
                                            }
                                    case .failure:
                                        Color.secondary.opacity(0.2)
                                            .frame(height: 100)
                                            .overlay(
                                                Image(systemName: "photo")
                                                    .foregroundStyle(.secondary)
                                            )
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                                Text(item.title)
                                    .font(.footnote)
                                    .foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("UI Playground")
            .overlay {
                if let selectedMedia {
                    FullscreenMediaViewer(
                        isPresented: $isViewerPresented,
                        media: selectedMedia.media,
                        config: selectedMedia.config,
                        thumbnailURL: selectedMedia.thumbnailURL,
                        previewImage: nil,
                        markupConfiguration: nil,
                        startsInMarkupMode: false
                    )
                    .onDisappear {
                        if !isViewerPresented {
                            self.selectedMedia = nil
                        }
                    }
                }
            }
            .onChange(of: isViewerPresented) { isPresented in
                if !isPresented {
                    selectedMedia = nil
                }
            }
        }
    }
}

#Preview {
    Uiplayground()
}
