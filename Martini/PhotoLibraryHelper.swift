import Photos
import UIKit

struct PhotoAccessAlert: Identifiable {
    let id = UUID()
    let message: String
}

enum PhotoSaveContext {
    case clip
    case board
}

enum PhotoSaveResult {
    case success
    case accessDenied
    case failure(Error)
}

enum PhotoLibraryAccessResult {
    case authorized
    case denied
}

enum PhotoLibraryHelper {
    static func saveImage(data: Data) async -> PhotoSaveResult {
        guard UIImage(data: data) != nil else {
            return .failure(NSError(domain: "PhotosSave", code: 3, userInfo: nil))
        }
        let accessResult = await requestPhotoLibraryAccess()
        guard accessResult == .authorized else { return .accessDenied }
        do {
            try await performPhotoLibraryChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
            return .success
        } catch {
            print("Failed to save image to Photos: \(error)")
            return .failure(error)
        }
    }

    static func saveVideo(url: URL) async -> PhotoSaveResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(NSError(domain: "PhotosSave", code: 2, userInfo: nil))
        }
        let accessResult = await requestPhotoLibraryAccess()
        guard accessResult == .authorized else { return .accessDenied }
        do {
            try await performPhotoLibraryChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .video, fileURL: url, options: nil)
            }
            return .success
        } catch {
            print("Failed to save video to Photos: \(error)")
            return .failure(error)
        }
    }

    static func accessDeniedMessage(for context: PhotoSaveContext) -> String {
        switch context {
        case .clip:
            return "Martini needs access to your Photos library to save clips. Please enable Photos access in Settings."
        case .board:
            return "Martini needs access to your Photos library to save boards. Please enable Photos access in Settings."
        }
    }

    private static func requestPhotoLibraryAccess() async -> PhotoLibraryAccessResult {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return .authorized
        case .notDetermined:
            let newStatus = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { result in
                    continuation.resume(returning: result)
                }
            }
            return (newStatus == .authorized || newStatus == .limited) ? .authorized : .denied
        default:
            return .denied
        }
    }

    private static func performPhotoLibraryChanges(_ changes: @escaping () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: NSError(domain: "PhotosSave", code: 1, userInfo: nil))
                }
            }
        }
    }
}
