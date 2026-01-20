//
//  MartiniLiveActivityModels.swift
//  Martini
//

import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

struct MartiniLiveActivityFrame: Codable, Hashable {
    let id: String
    let title: String
    let number: Int
    let thumbnailUrl: String?
    let localThumbnailFilename: String?
    let creativeAspectRatio: String?
    let crop: String?
}

#if canImport(ActivityKit)
@available(iOS 16.1, *)
enum MartiniLiveActivityShared {
    static let appGroupIdentifier = "group.com.martini.martinilive"
    static let thumbnailDirectoryName = "LiveActivityThumbnails"
}

@available(iOS 16.1, *)
struct MartiniLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        let currentFrame: MartiniLiveActivityFrame?
        let nextFrame: MartiniLiveActivityFrame?
        let completed: Int
        let total: Int
    }

    let projectTitle: String
}
#endif
