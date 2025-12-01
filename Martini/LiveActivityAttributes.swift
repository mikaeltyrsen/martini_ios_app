#if canImport(ActivityKit)
import ActivityKit
import Foundation

struct FrameActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var currentFrameNumber: Int
        var currentFrameImageURL: URL?
        var completedFrames: Int
        var totalFrames: Int
        var upNextFrameNumber: Int?
        var upNextImageURL: URL?
    }

    var projectName: String
}
#endif
