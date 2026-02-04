import Foundation
import CoreGraphics

enum UploadCompressionSetting: String, CaseIterable, Identifiable {
    case original
    case large
    case medium
    case small

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original:
            return "Original"
        case .large:
            return "Large"
        case .medium:
            return "Medium"
        case .small:
            return "Small"
        }
    }

    var detailLines: [String] {
        switch self {
        case .original:
            return [
                "JPG",
                "No resize",
                "92-95% quality"
            ]
        case .large:
            return [
                "Max 2560px",
                "80% quality"
            ]
        case .medium:
            return [
                "Max 1920px",
                "72% quality"
            ]
        case .small:
            return [
                "Max 720px",
                "55% quality"
            ]
        }
    }

    var maxPixelDimension: CGFloat? {
        switch self {
        case .original:
            return nil
        case .large:
            return 2560
        case .medium:
            return 1920
        case .small:
            return 720
        }
    }

    var jpegQuality: CGFloat {
        switch self {
        case .original:
            return 0.93
        case .large:
            return 0.80
        case .medium:
            return 0.72
        case .small:
            return 0.55
        }
    }
}
