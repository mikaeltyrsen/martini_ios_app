//
//  Models.swift
//  Martini
//
//  Data models for the Martini app
//

import Foundation

// MARK: - Creative Model

struct Creative: Codable, Identifiable {
    let id: String
    let shootId: String
    let title: String
    let order: Int
    let isArchived: Int
    let isLive: Int
    let totalFrames: Int
    let completedFrames: Int
    let remainingFrames: Int
    let primaryFrameId: String?
    let frameFileName: String?
    let frameImage: String?
    let frameBoardType: String?
    let frameStatus: String?
    let frameNumber: Int?
    let image: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case shootId = "shoot_id"
        case title
        case order
        case isArchived = "is_archived"
        case isLive = "is_live"
        case totalFrames = "total_frames"
        case completedFrames = "completed_frames"
        case remainingFrames = "remaining_frames"
        case primaryFrameId = "primary_frame_id"
        case frameFileName = "frame_file_name"
        case frameImage = "frame_image"
        case frameBoardType = "frame_board_type"
        case frameStatus = "frame_status"
        case frameNumber = "frame_number"
        case image
    }
    
    // Computed property for progress percentage
    var progressPercentage: Double {
        guard totalFrames > 0 else { return 0 }
        return Double(completedFrames) / Double(totalFrames) * 100
    }
}

// MARK: - API Response Models

struct CreativesResponse: Codable {
    let success: Bool
    let creatives: [Creative]
    let error: String?
}
