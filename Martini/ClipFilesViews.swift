import SwiftUI
import QuickLook
import UIKit

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct FilesSheet: View {
    let title: String
    @Binding var clips: [Clip]
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    let onReload: () async -> Void
    let onMediaPreview: (Clip) -> Void
    @State private var selectedClip: Clip?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .task {
                    await onReload()
                }
                .alert("Error", isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) { errorMessage = nil }
                } message: {
                    Text(errorMessage ?? "Unknown error")
                }
        }
    }

    private var content: some View {
        Group {
            if !clips.isEmpty {
                List(clips) { clip in
                    ClipRow(clip: clip) {
                        handlePreview(clip)
                    }
                }
                .listStyle(.plain)
            } else if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading clips...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No files found")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $selectedClip) { clip in
            ClipPreviewView(clip: clip)
                .presentationDragIndicator(.visible)
        }
    }

    private func handlePreview(_ clip: Clip) {
        if clip.isVideo || clip.isImage {
            onMediaPreview(clip)
        } else {
            selectedClip = clip
        }
    }
}

struct ClipRow: View {
    let clip: Clip
    let onPreview: () -> Void
    @State private var shareItem: ShareItem?
    @State private var photoAccessAlert: PhotoLibraryHelper.PhotoAccessAlert?
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            ClipThumbnailView(clip: clip)
                .frame(width: 48, height: 48)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(clip.displayName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let size = clip.formattedFileSize {
                        Label(size, systemImage: "externaldrive.badge.icloud")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if clip.isVideo {
                        Label("Video", systemImage: "video")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if clip.isImage {
                        Label("Image", systemImage: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()

            Menu {
                Button("Preview") { onPreview() }
                if let url = clip.fileURL {
                    Button {
                        shareClip(url: url)
                    } label: {
                        Label("Share/Save", systemImage: "square.and.arrow.up")
                    }
                }
                if clip.isImage || clip.isVideo {
                    Button(role: .none) {
                        saveToPhotos(clip: clip)
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onPreview() }
        .sheet(item: $shareItem) { item in
            ActivityView(activityItems: [item.url])
        }
        .alert(item: $photoAccessAlert) { alert in
            Alert(
                title: Text("Photos Access Needed"),
                message: Text(alert.message),
                primaryButton: .default(Text("Open Settings")) {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        openURL(settingsURL)
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func saveToPhotos(clip: Clip) {
        guard let url = clip.fileURL else { return }
        Task {
            do {
                let result: PhotoSaveResult
                if clip.isVideo {
                    let localURL = try await localVideoURL(for: url)
                    result = await PhotoLibraryHelper.saveVideo(url: localURL)
                } else {
                    guard let data = await ImageCache.shared.data(for: url) else {
                        throw URLError(.cannotDecodeContentData)
                    }
                    result = await PhotoLibraryHelper.saveImage(data: data)
                }

                if case .accessDenied = result {
                    photoAccessAlert = PhotoLibraryHelper.PhotoAccessAlert(
                        message: PhotoLibraryHelper.accessDeniedMessage(for: .clip)
                    )
                }
            } catch {
                print("Failed to save clip to Photos: \(error)")
            }
        }
    }

    private func shareClip(url: URL) {
        Task {
            do {
                let localURL = try await localShareURL(for: url)
                shareItem = ShareItem(url: localURL)
            } catch {
                print("Failed to prepare clip for sharing: \(error)")
            }
        }
    }

    private func localShareURL(for url: URL) async throws -> URL {
        if clip.isImage, let data = await ImageCache.shared.data(for: url) {
            return try writeTemporaryFile(data: data, originalURL: url)
        }

        if clip.isVideo, let cached = await cachedVideoURL(for: url) {
            return cached
        }

        return try await downloadToTemporaryFile(url: url)
    }

    private func localVideoURL(for url: URL) async throws -> URL {
        if let cached = await cachedVideoURL(for: url) {
            return cached
        }

        return try await downloadToTemporaryFile(url: url)
    }

    private func cachedVideoURL(for url: URL) async -> URL? {
        if let cached = VideoCacheManager.shared.existingCachedFile(for: url) {
            return cached
        }

        return await withCheckedContinuation { continuation in
            VideoCacheManager.shared.fetchCachedURL(for: url) { cachedURL in
                continuation.resume(returning: cachedURL)
            }
        }
    }

    private func downloadToTemporaryFile(url: URL) async throws -> URL {
        let (downloadedURL, _) = try await URLSession.shared.download(from: url)
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: downloadedURL, to: destinationURL)
        return destinationURL
    }

    private func writeTemporaryFile(data: Data, originalURL: URL) throws -> URL {
        let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(originalURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try data.write(to: destinationURL, options: .atomic)
        return destinationURL
    }
}

struct ClipThumbnailView: View {
    let clip: Clip

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.secondary.opacity(0.15))
            if let url = clip.thumbnailURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        ProgressView()
                    case .failure:
                        Image(systemName: clip.systemIconName)
                            .foregroundStyle(.secondary)
                    @unknown default:
                        Image(systemName: clip.systemIconName)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: clip.systemIconName)
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
    }
}

struct ClipPreviewView: View {
    let clip: Clip
    @State private var localPreviewURL: URL?
    @State private var isLoadingPreview = false
    @State private var previewErrorMessage: String?

    var body: some View {
        VStack {
            if clip.isVideo, let url = clip.fileURL {
                CachedVideoPlayerView(url: url)
            } else if clip.isImage, let url = clip.fileURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .empty:
                        ProgressView()
                    case .failure:
                        Text("Unable to load image.")
                            .foregroundStyle(.secondary)
                    @unknown default:
                        Text("Unable to load image.")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let localPreviewURL {
                QuickLookPreview(url: localPreviewURL)
            } else if isLoadingPreview {
                ProgressView()
            } else {
                Text(previewErrorMessage ?? "Unable to load clip")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .task(id: clip.id) {
            await loadPreview()
        }
    }

    private func loadPreview() async {
        guard !clip.isVideo, !clip.isImage else { return }
        guard localPreviewURL == nil else { return }
        guard let remoteURL = clip.fileURL else {
            previewErrorMessage = "Unable to load file."
            return
        }
        isLoadingPreview = true
        defer { isLoadingPreview = false }
        do {
            let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
            let destinationURL = FileManager.default.temporaryDirectory.appendingPathComponent(remoteURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: tempURL, to: destinationURL)
            localPreviewURL = destinationURL
        } catch {
            previewErrorMessage = "Unable to load file."
            print("Failed to download preview file: \(error)")
        }
    }
}

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
