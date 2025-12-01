import CryptoKit
import SwiftUI

actor ImageCache {
    static let shared = ImageCache()

    private let memoryCache = NSCache<NSURL, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private init() {
        let directories = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let folder = directories.first?.appendingPathComponent("MartiniImageCache", isDirectory: true)
        cacheDirectory = folder ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MartiniImageCache", isDirectory: true)

        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    func image(for url: URL) async -> UIImage? {
        let nsURL = url as NSURL

        if let cached = memoryCache.object(forKey: nsURL) {
            return cached
        }

        if let diskImage = loadFromDisk(for: url) {
            memoryCache.setObject(diskImage, forKey: nsURL)
            return diskImage
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }
            memoryCache.setObject(image, forKey: nsURL)
            saveToDisk(data: data, for: url)
            return image
        } catch {
            return nil
        }
    }

    private func loadFromDisk(for url: URL) -> UIImage? {
        let path = cacheFileURL(for: url)
        guard fileManager.fileExists(atPath: path.path) else { return nil }
        guard let data = try? Data(contentsOf: path) else { return nil }
        return UIImage(data: data)
    }

    private func saveToDisk(data: Data, for url: URL) {
        let path = cacheFileURL(for: url)
        try? data.write(to: path, options: .atomic)
    }

    private func cacheFileURL(for url: URL) -> URL {
        let hashed = SHA256.hash(data: Data(url.absoluteString.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
        return cacheDirectory.appendingPathComponent(hashed)
    }
}

struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    var body: some View {
        content(phase)
            .task(id: url) {
                await loadImage()
            }
    }

    private func loadImage() async {
        guard let url else {
            await MainActor.run { phase = .failure(ImageCacheError.invalidURL) }
            return
        }

        await MainActor.run { phase = .empty }

        if let image = await ImageCache.shared.image(for: url) {
            await MainActor.run { phase = .success(Image(uiImage: image)) }
        } else {
            await MainActor.run { phase = .failure(ImageCacheError.decodingFailed) }
        }
    }
}

private enum ImageCacheError: Error {
    case invalidURL
    case decodingFailed
}
