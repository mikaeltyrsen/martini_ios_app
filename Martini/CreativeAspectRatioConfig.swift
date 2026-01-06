import CoreGraphics
import Foundation

enum CreativeAspectRatioConfig {
    struct Entry: Identifiable {
        let id = UUID()
        let label: String
        let ratioString: String
        let ratio: CGFloat
    }

    static let minDescriptionRatio: CGFloat = 0.30
    static let maxDescriptionRatio: CGFloat = 0.65

    static let entries: [Entry] = [
        Entry(label: "Standard (HD / Streaming)", ratioString: "16:9", ratio: 16.0 / 9.0),
        Entry(label: "Flat (Theatrical)", ratioString: "1.85:1", ratio: 1.85),
        Entry(label: "Univisium", ratioString: "2.00:1", ratio: 2.0),
        Entry(label: "Scope (Anamorphic)", ratioString: "2.39:1", ratio: 2.39),
        Entry(label: "Classic / Archive", ratioString: "4:3", ratio: 4.0 / 3.0),
        Entry(label: "Vertical Video (Reels / TikTok)", ratioString: "9:16", ratio: 9.0 / 16.0),
        Entry(label: "Instagram Feed", ratioString: "4:5", ratio: 4.0 / 5.0),
        Entry(label: "Square", ratioString: "1:1", ratio: 1.0),
        Entry(label: "Vertical Photo", ratioString: "3:4", ratio: 3.0 / 4.0),
        Entry(label: "Photography", ratioString: "3:2", ratio: 3.0 / 2.0),
        Entry(label: "Print / Editorial", ratioString: "5:4", ratio: 5.0 / 4.0),
        Entry(label: "IMAX Digital", ratioString: "1.90:1", ratio: 1.9),
        Entry(label: "DCI Native", ratioString: "17:9", ratio: 17.0 / 9.0)
    ]

    private static let ratioBounds: (min: CGFloat, max: CGFloat) = {
        let ratios = entries.map(\.$ratio)
        let minRatio = ratios.min() ?? (9.0 / 16.0)
        let maxRatio = ratios.max() ?? (2.39)
        return (minRatio, maxRatio)
    }()

    static func descriptionRatio(for ratioString: String?) -> CGFloat {
        guard let ratioString else {
            return descriptionRatio(for: 16.0 / 9.0)
        }

        if let ratio = FrameLayout.aspectRatio(from: ratioString) {
            return descriptionRatio(for: ratio)
        }

        return descriptionRatio(for: 16.0 / 9.0)
    }

    static func descriptionRatio(for ratio: CGFloat) -> CGFloat {
        let minRatio = ratioBounds.min
        let maxRatio = ratioBounds.max

        guard maxRatio > minRatio else {
            return maxDescriptionRatio
        }

        let clampedRatio = min(max(ratio, minRatio), maxRatio)
        let t = (clampedRatio - minRatio) / (maxRatio - minRatio)
        return maxDescriptionRatio - (t * (maxDescriptionRatio - minDescriptionRatio))
    }
}
