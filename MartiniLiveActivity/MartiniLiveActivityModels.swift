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
}

#if canImport(ActivityKit)
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
