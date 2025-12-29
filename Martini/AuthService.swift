//
//  AuthService.swift
//  Martini
//
//  Authentication service for managing login tokens
//

import Foundation

struct FrameUpdateEvent: Equatable {
    let frameId: String
    let context: FrameUpdateContext

    private let identifier = UUID()

    static func == (lhs: FrameUpdateEvent, rhs: FrameUpdateEvent) -> Bool {
        lhs.identifier == rhs.identifier
    }
}

enum FrameUpdateContext: Equatable {
    case localStatusChange
    case websocket(event: String)
}

struct ScheduleUpdateEvent: Equatable {
    let eventName: String

    private let identifier = UUID()

    static func == (lhs: ScheduleUpdateEvent, rhs: ScheduleUpdateEvent) -> Bool {
        lhs.identifier == rhs.identifier
    }
}

@MainActor
protocol ConnectionMonitoring: AnyObject {
    func registerNetworkSuccess()
    func registerImmediateFailure(for error: Error)
}

@MainActor
class AuthService: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var projectId: String?
    @Published var projectTitle: String?
    @Published var accessCode: String?
    @Published var token: String?
    //@Published var bearerTokenOverride: String? = "d9c4dafc0eaa40b5d0025ef0a622a5bff35ebd2ccf06a4f66d99d62602405ed2853732f5b2acc2350f447f8083178c58105b2b79a1c559a67b1bfaa5c7c7d04d"
    @Published var bearerTokenOverride: String?
    @Published var debugInfo: DebugInfo?
    @Published var creatives: [Creative] = []
    @Published var isLoadingCreatives: Bool = false
    @Published var projectDetails: ProjectDetails?
    @Published var cachedSchedule: ProjectSchedule?
    @Published var fetchedSchedules: [ProjectSchedule] = []
    @Published var frames: [Frame] = []
    @Published var frameUpdateEvent: FrameUpdateEvent?
    @Published var scheduleUpdateEvent: ScheduleUpdateEvent?
    @Published var isLoadingFrames: Bool = false
    @Published var isScheduleActive: Bool = false
    @Published var isLoadingProjectDetails: Bool = false
    @Published var pendingDeepLink: String?
    
    private let tokenHashKey = "martini_token_hash"
    private let projectIdKey = "martini_project_id"
    private let projectTitleKey = "martini_project_title"
    private let accessCodeKey = "martini_access_code"
    private let cachedCreativesKeyPrefix = "martini_cached_creatives_"
    private let cachedFramesKeyPrefix = "martini_cached_frames_"
    private let baseScriptsURL = "https://dev.staging.trymartini.com/scripts/"
    private let scheduleCache = ScheduleCache.shared
    private var creativesFetchTask: Task<Void, Error>?
    private var projectDetailsFetchTask: Task<Void, Error>?
    private let connectionMonitor: (any ConnectionMonitoring)?

    init(connectionMonitor: (any ConnectionMonitoring)? = nil) {
        self.connectionMonitor = connectionMonitor
        loadAuthData()
    }

    private enum APIEndpoint: String {
        case authLive = "auth/live.php"
        case project = "projects/get_project.php"
        case creatives = "creatives/get_creatives.php"
        case frames = "frames/get.php"
        case updateFrameStatus = "frames/update_status.php"
        case updateBoard = "frames/update_board.php"
        case removeImage = "frames/remove_image.php"
        case schedule = "schedules/fetch.php"
        case clips = "clips/fetch.php"
        case comments = "comments/get_comments.php"

        var path: String { rawValue }
    }

    private func url(for endpoint: APIEndpoint) throws -> URL {
        guard let url = URL(string: "\(baseScriptsURL)\(endpoint.path)") else {
            throw AuthError.invalidURL
        }
        return url
    }

    func currentBearerToken() -> String? {
        if let override = bearerTokenOverride, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("Overriding Bearer Token: \(override)")
            return override
        }
        return token
    }

    func handleDeepLink(_ url: URL) {
        let qrString = url.absoluteString
        print("🌐 Received deeplink: \(qrString)")

        do {
            let (accessCode, _) = try parseQRCode(qrString)

            if let accessCode {
                Task {
                    do {
                        try await self.authenticate(withQRCode: qrString, manualAccessCode: accessCode)
                    } catch {
                        print("❌ Failed to authenticate from deeplink: \(error.localizedDescription)")
                    }
                }
            } else {
                if isAuthenticated {
                    logout()
                }
                pendingDeepLink = qrString
            }
        } catch {
            print("❌ Failed to parse deeplink: \(error.localizedDescription)")
        }
    }

    private func authorizedRequest(for endpoint: APIEndpoint, method: String = "POST", body: [String: Any]? = nil) throws -> URLRequest {
        guard let token = currentBearerToken() else {
            throw AuthError.noAuth
        }

        let url = try url(for: endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return request
    }

    // Load auth data from UserDefaults
    func loadAuthData() {
        if let projectId = UserDefaults.standard.string(forKey: projectIdKey),
           let token = UserDefaults.standard.string(forKey: tokenHashKey) {
            self.projectId = projectId
            self.accessCode = UserDefaults.standard.string(forKey: accessCodeKey)
            self.projectTitle = UserDefaults.standard.string(forKey: projectTitleKey)
            self.token = token
            self.isAuthenticated = true
            loadCachedProjectData(for: projectId)

            // Automatically refresh project details, creatives, and frames when a token is already stored
            Task {
                try? await self.fetchProjectCreativesAndFrames()
            }
        }
    }

    // Save auth data to UserDefaults
    private func saveAuthData(projectId: String, projectTitle: String?, accessCode: String, token: String) {
        UserDefaults.standard.set(projectId, forKey: projectIdKey)
        UserDefaults.standard.set(projectTitle, forKey: projectTitleKey)
        UserDefaults.standard.set(accessCode, forKey: accessCodeKey)
        UserDefaults.standard.set(token, forKey: tokenHashKey)
        self.projectId = projectId
        self.projectTitle = projectTitle
        self.accessCode = accessCode
        self.token = token
        self.isAuthenticated = true
    }
    
    // Authenticate with QR code data and optional manual access code
    func authenticate(withQRCode qrCode: String, manualAccessCode: String? = nil) async throws {
        print("🔍 Starting authentication with QR: \(qrCode)")
        
        // Parse and validate the QR code URL
        let parsedAccessCode: String?
        let projectId: String
        
        do {
            (parsedAccessCode, projectId) = try parseQRCode(qrCode)
            print("🔍 Parsed QR - accessCode: \(parsedAccessCode ?? "nil"), projectId: \(projectId)")
        } catch {
            print("🔍 Failed to parse QR code: \(error)")
            // Set debug info even for parse errors
            self.debugInfo = DebugInfo(
                requestURL: "Parse Error",
                requestBody: "QR Code: \(qrCode)",
                responseStatusCode: -1,
                responseBody: "Error: \(error.localizedDescription)"
            )
            throw error
        }
        
        // Use parsed access code or manual entry
        guard let accessCode = parsedAccessCode ?? manualAccessCode else {
            print("🔍 No access code provided")
            throw AuthError.missingAccessCode
        }
        
        // Send authentication request to PHP endpoint
        let url = try url(for: .authLive)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "projectId": projectId,
            "accessCode": accessCode
        ]
        request.httpBody = try JSONEncoder().encode(body)
        
        // DEBUG: Store request info
        let requestJSON = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "Unable to encode request"
        print("🔍 Sending request to: \(url.absoluteString)")
        print("🔍 Request body: \(requestJSON)")
        
        // Store initial debug info with request
        self.debugInfo = DebugInfo(
            requestURL: url.absoluteString,
            requestBody: requestJSON,
            responseStatusCode: 0,
            responseBody: "Waiting for response..."
        )
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await performRequest(request)
            print("🔍 Received response")
        } catch {
            print("🔍 Network error: \(error)")
            // Update debug info with network error
            self.debugInfo = DebugInfo(
                requestURL: url.absoluteString,
                requestBody: requestJSON,
                responseStatusCode: -2,
                responseBody: "Network Error: \(error.localizedDescription)"
            )
            throw error
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            // Update debug info with error
            self.debugInfo = DebugInfo(
                requestURL: url.absoluteString,
                requestBody: requestJSON,
                responseStatusCode: 0,
                responseBody: "Invalid HTTP response"
            )
            throw AuthError.invalidResponse
        }
        
        // DEBUG: Update with response info
        let responseJSON = String(data: data, encoding: .utf8) ?? "Unable to decode response"
        self.debugInfo = DebugInfo(
            requestURL: url.absoluteString,
            requestBody: requestJSON,
            responseStatusCode: httpResponse.statusCode,
            responseBody: responseJSON
        )
        print("🔍 DEBUG INFO SET:")
        print("Request: \(requestJSON)")
        print("Response (\(httpResponse.statusCode)): \(responseJSON)")
        
        guard httpResponse.statusCode == 200 else {
            // Try to parse error message from response
            if let errorResponse = try? JSONDecoder().decode(AuthErrorResponse.self, from: data) {
                throw AuthError.authenticationFailedWithMessage(errorResponse.error)
            }
            throw AuthError.authenticationFailed(statusCode: httpResponse.statusCode)
        }
        
        // Parse response
        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        
        guard authResponse.success else {
            print("❌ Auth response failed: \(authResponse.error ?? "Unknown error")")
            throw AuthError.authenticationFailedWithMessage(authResponse.error ?? "Unknown error")
        }
        
        print("✅ Authentication successful!")
        guard let token = authResponse.token else {
            throw AuthError.invalidResponse
        }

        print("🔑 Received token: \(token.prefix(20))...")

        // Save auth data (project ID, access code, project title, and token)
        saveAuthData(
            projectId: projectId,
            projectTitle: authResponse.projectTitle,
            accessCode: accessCode,
            token: token
        )
        
        print("💾 Saved auth data - projectId: \(projectId)")
        print("🎬 About to fetch project details, creatives, and frames...")

        // Fetch project details, creatives, and frames after successful authentication
        do {
            try await fetchProjectCreativesAndFrames()
        } catch {
            print("❌ Failed to fetch project data: \(error)")
            throw error
        }
    }
    
    // Parse QR code URL and extract project ID, and optionally access code
    // Format: https://trymartini.com/*/<uuid7> (needs manual code entry)
    //     or: https://trymartini.com/*/<uuid7>-<code> (code included)
    func parseQRCode(_ qrCode: String) throws -> (accessCode: String?, projectId: String) {
        print("🔍 Parsing QR code: \(qrCode)")
        let pattern = "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})(?:-([0-9a-zA-Z]{4}))?"
        let regex = try NSRegularExpression(pattern: pattern)
        let nsString = qrCode as NSString

        if let match = regex.firstMatch(in: qrCode, range: NSRange(location: 0, length: nsString.length)) {
            let projectIdRange = match.range(at: 1)
            let accessCodeRange = match.range(at: 2)

            guard projectIdRange.location != NSNotFound else {
                throw AuthError.invalidQRCode
            }

            let projectId = nsString.substring(with: projectIdRange)
            let accessCode = accessCodeRange.location != NSNotFound ? nsString.substring(with: accessCodeRange) : nil

            print("🔍 Extracted - projectId: \(projectId), accessCode: \(accessCode ?? "(needs manual entry)")")
            return (accessCode, projectId)
        }
        
        print("🔍 Could not find valid code pattern")
        throw AuthError.invalidQRCode
    }
    
    // Make authenticated API call
    private func makeAuthenticatedRequest(to endpoint: APIEndpoint) async throws -> Data {
        guard projectId != nil else {
            throw AuthError.noAuth
        }

        let request = try authorizedRequest(for: endpoint, method: "GET")
        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            // Auth is invalid, logout
            logout()
            throw AuthError.unauthorized
        }

        guard httpResponse.statusCode == 200 else {
            throw AuthError.requestFailed(statusCode: httpResponse.statusCode)
        }

        return data
    }

    func fetchProjectCreativesAndFrames() async throws {
        try await fetchProjectDetails()
        try await fetchCreatives()
        try await fetchFrames()
    }
    
    // Fetch creatives for the current project
    func fetchCreatives(pullAll: Bool = false) async throws {
        guard let projectId = projectId else {
            throw AuthError.noAuth
        }

        if let existingTask = creativesFetchTask {
            return try await existingTask.value
        }

        let fetchTask: Task<Void, Error> = Task { @MainActor in
            isLoadingCreatives = true
            defer {
                isLoadingCreatives = false
                creativesFetchTask = nil
            }

            var body: [String: Any] = [
                "projectId": projectId,
                "pullAll": pullAll
            ]

            var request = try authorizedRequest(for: .creatives, body: body)

            let requestJSON = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "Unable to encode"
            print("📤 Fetching creatives...")
            print("🔗 URL: \(request.url?.absoluteString ?? "unknown")")
            print("📝 Request body: \(requestJSON)")
            
            let (data, response) = try await performRequest(request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
                print("❌ Failed to fetch creatives - Status: \(httpResponse.statusCode)")
                print("📝 Response: \(errorBody)")
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    logout()
                    throw AuthError.unauthorized
                }
                throw AuthError.requestFailed(statusCode: httpResponse.statusCode)
            }
            
            print("📥 Creatives response received (\(httpResponse.statusCode))")
            
            let decoder = JSONDecoder()
            let creativesResponse = try decoder.decode(CreativesResponse.self, from: data)

            guard creativesResponse.success else {
                print("❌ Creatives response failed: \(creativesResponse.error ?? "Unknown error")")
                throw AuthError.authenticationFailedWithMessage(creativesResponse.error ?? "Failed to fetch creatives")
            }

            if (self.projectId ?? "").isEmpty, let responseProjectId = creativesResponse.projectId, !responseProjectId.isEmpty {
                self.projectId = responseProjectId
                UserDefaults.standard.set(responseProjectId, forKey: projectIdKey)
            }
            
            self.creatives = creativesResponse.creatives
            cacheCreatives(creativesResponse.creatives, for: projectId)
            print("✅ Successfully fetched \(creatives.count) creatives")
            for (index, creative) in creatives.prefix(3).enumerated() {
                print("  \(index + 1). \(creative.title) - \(creative.completedFrames)/\(creative.totalFrames) frames")
            }
            if creatives.count > 3 {
                print("  ... and \(creatives.count - 3) more")
            }
        }

        creativesFetchTask = fetchTask
        do {
            try await fetchTask.value
        } catch {
            creativesFetchTask = nil
            throw error
        }
    }

    // Fetch frames for the current project
    func fetchFrames() async throws {
        guard let projectId = projectId else {
            throw AuthError.noAuth
        }

        isLoadingFrames = true
        defer { isLoadingFrames = false }

        let body: [String: Any] = [
            "projectId": projectId,
        ]

        var request = try authorizedRequest(for: .frames, body: body)

        let requestJSON = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "Unable to encode"
        print("📤 Fetching frames...")
        print("🔗 URL: \(request.url?.absoluteString ?? "unknown")")
        print("📝 Request body: \(requestJSON)")

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Failed to fetch frames - Status: \(httpResponse.statusCode)")
            print("📝 Response: \(errorBody)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                logout()
                throw AuthError.unauthorized
            }
            throw AuthError.requestFailed(statusCode: httpResponse.statusCode)
        }

        print("📥 Frames response received (\(httpResponse.statusCode))")

        let decoder = JSONDecoder()
        let framesResponse = try decoder.decode(FramesResponse.self, from: data)

        guard framesResponse.success else {
            print("❌ Frames response failed: \(framesResponse.error ?? "Unknown error")")
            throw AuthError.authenticationFailedWithMessage(framesResponse.error ?? "Failed to fetch frames")
        }

        self.frames = framesResponse.frames
        cacheFrames(framesResponse.frames, for: projectId)
        self.isScheduleActive = framesResponse.frames.contains { frame in
            if let schedule = frame.schedule, !schedule.isEmpty { return true }
            return false
        }
        print("✅ Successfully fetched \(frames.count) frames")
    }

    func fetchClips(shootId: String, frameId: String, creativeId: String) async throws -> [Clip] {
        let body: [String: Any] = [
            "shootId": shootId,
            "frameId": frameId,
            "creativeId": creativeId
        ]

        var request = try authorizedRequest(for: .clips, body: body)

        let requestJSON = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "Unable to encode"
        print("📤 Fetching clips...")
        print("🔗 URL: \(request.url?.absoluteString ?? "unknown")")
        print("📝 Request body: \(requestJSON)")

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Failed to fetch clips - Status: \(httpResponse.statusCode)")
            print("📝 Response: \(errorBody)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                logout()
                throw AuthError.unauthorized
            }
            throw AuthError.requestFailed(statusCode: httpResponse.statusCode)
        }

        print("📥 Clips response received (\(httpResponse.statusCode))")

        let decoder = JSONDecoder()
        let clipsResponse = try decoder.decode(ClipsResponse.self, from: data)

        guard clipsResponse.success else {
            print("❌ Clips response failed: \(clipsResponse.error ?? "Unknown error")")
            throw AuthError.authenticationFailedWithMessage(clipsResponse.error ?? "Failed to fetch clips")
        }

        print("✅ Successfully fetched \(clipsResponse.clips.count) clips")
        return clipsResponse.clips
    }

    func fetchComments(creativeId: String, frameId: String?) async throws -> CommentsResponse {
        var body: [String: Any] = [
            "creativeId": creativeId
        ]

        if let frameId {
            body["frameId"] = frameId
        }

        var request = try authorizedRequest(for: .comments, body: body)

        let requestJSON = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "Unable to encode"
        print("📤 Fetching comments...")
        print("🔗 URL: \(request.url?.absoluteString ?? "unknown")")
        print("📝 Request body: \(requestJSON)")

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Failed to fetch comments - Status: \(httpResponse.statusCode)")
            print("📝 Response: \(errorBody)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                logout()
                throw AuthError.unauthorized
            }
            throw AuthError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let responseJSON = String(data: data, encoding: .utf8) ?? "Unable to decode"
        print("📥 Comments response received (\(httpResponse.statusCode)):")
        print(responseJSON)

        let decoder = JSONDecoder()
        let commentsResponse = try decoder.decode(CommentsResponse.self, from: data)

        guard commentsResponse.success else {
            print("❌ Comments response failed: \(commentsResponse.error ?? "Unknown error")")
            throw AuthError.authenticationFailedWithMessage(commentsResponse.error ?? "Failed to fetch comments")
        }

        print("✅ Successfully fetched \(commentsResponse.comments.count) comments")
        return commentsResponse
    }

    func fetchProjectDetails() async throws {
        guard let projectId = projectId else {
            throw AuthError.noAuth
        }

        if let existingTask = projectDetailsFetchTask {
            return try await existingTask.value
        }

        let fetchTask: Task<Void, Error> = Task { @MainActor in
            isLoadingProjectDetails = true
            defer {
                isLoadingProjectDetails = false
                projectDetailsFetchTask = nil
            }

            let body: [String: Any] = [
                "projectId": projectId
            ]

            var request = try authorizedRequest(for: .project, body: body)

            let requestJSON = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "Unable to encode"
            print("📤 Fetching project details...")
            print("🔗 URL: \(request.url?.absoluteString ?? "unknown")")
            print("📝 Request body: \(requestJSON)")

            let (data, response) = try await performRequest(request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AuthError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
                print("❌ Failed to fetch project details - Status: \(httpResponse.statusCode)")
                print("📝 Response: \(errorBody)")
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    logout()
                    throw AuthError.unauthorized
                }
                throw AuthError.requestFailed(statusCode: httpResponse.statusCode)
            }

            print("📥 Project response received (\(httpResponse.statusCode))")

            let decoder = JSONDecoder()
            let projectResponse = try decoder.decode(ProjectDetails.self, from: data)

            guard projectResponse.success else {
                print("❌ Project response failed")
                throw AuthError.authenticationFailedWithMessage("Failed to fetch project details")
            }

            self.projectDetails = projectResponse
            self.isScheduleActive = projectResponse.activeSchedule != nil || frames.contains { frame in
                if let schedule = frame.schedule, !schedule.isEmpty { return true }
                return false
            }

            print("✅ Successfully fetched project details for \(projectResponse.name)")
        }

        projectDetailsFetchTask = fetchTask
        do {
            try await fetchTask.value
        } catch {
            projectDetailsFetchTask = nil
            throw error
        }
    }

    func publishFrameUpdate(frameId: String, context: FrameUpdateContext) {
        frameUpdateEvent = FrameUpdateEvent(frameId: frameId, context: context)
    }

    func publishScheduleUpdate(eventName: String) {
        scheduleUpdateEvent = ScheduleUpdateEvent(eventName: eventName)
    }

    func updateFramesAspectRatio(creativeId: String, aspectRatio: String) {
        var didChange = false
        let updatedFrames = frames.map { frame in
            guard frame.creativeId == creativeId else { return frame }
            let updatedFrame = frame.updatingCreativeAspectRatio(aspectRatio)
            if updatedFrame.creativeAspectRatio != frame.creativeAspectRatio {
                didChange = true
            }
            return updatedFrame
        }

        guard didChange else { return }

        frames = updatedFrames

        if let projectId {
            cacheFrames(updatedFrames, for: projectId)
        }

        for frame in updatedFrames where frame.creativeId == creativeId {
            publishFrameUpdate(frameId: frame.id, context: .websocket(event: "creative-aspect-ratio-updated"))
        }
    }

    func updateFrameStatus(id: String, to status: FrameStatus) async throws -> Frame {
        guard let projectId else {
            throw AuthError.noAuth
        }

        let body: [String: Any] = [
            "project": projectId,
            "id": id,
            "status": status.requestValue
        ]

        var request = try authorizedRequest(for: .updateFrameStatus, body: body)

        let requestJSON = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "Unable to encode"
        print("📤 Updating frame status...")
        print("🔗 URL: \(request.url?.absoluteString ?? "unknown")")
        print("📝 Request body: \(requestJSON)")

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Failed to update frame status - Status: \(httpResponse.statusCode)")
            print("📝 Response: \(errorBody)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                logout()
                throw AuthError.unauthorized
            }
            throw AuthError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let responseJSON = String(data: data, encoding: .utf8) ?? "Unable to decode"
        print("📥 Update status response received (\(httpResponse.statusCode)):")
        print(responseJSON)

        let decoder = JSONDecoder()
        let statusResponse = try decoder.decode(UpdateFrameStatusResponse.self, from: data)

        guard statusResponse.success else {
            print("❌ Update status response failed: \(statusResponse.error ?? "Unknown error")")
            throw AuthError.authenticationFailedWithMessage(statusResponse.error ?? "Failed to update frame status")
        }

        let updatedFrame: Frame
        if let responseFrame = statusResponse.frame {
            updatedFrame = responseFrame
        } else {
            guard let existingIndex = frames.firstIndex(where: { $0.id == id }) else {
                throw AuthError.authenticationFailedWithMessage("Updated frame not found")
            }
            updatedFrame = frames[existingIndex].updatingStatus(status)
        }

        if let index = frames.firstIndex(where: { $0.id == updatedFrame.id }) {
            frames[index] = updatedFrame
        }
        cacheFrames(frames, for: projectId)

        publishFrameUpdate(frameId: updatedFrame.id, context: .localStatusChange)
        return updatedFrame
    }

    func renameBoard(frameId: String, boardId: String, label: String) async throws {
        guard let projectId else {
            throw AuthError.noAuth
        }

        let body: [String: Any] = [
            "projectId": projectId,
            "frameId": frameId,
            "action": "rename",
            "boardId": boardId,
            "label": label
        ]

        let data = try await sendBoardRequest(body: body, logLabel: "Renaming board")
        let response = try JSONDecoder().decode(UpdateBoardResponse.self, from: data)
        try await applyBoardUpdate(response, fallbackFrameId: frameId)
    }

    func deleteBoard(frameId: String, boardId: String) async throws {
        guard let projectId else {
            throw AuthError.noAuth
        }

        let body: [String: Any] = [
            "projectId": projectId,
            "frameId": frameId,
            "action": "delete",
            "boardId": boardId
        ]

        let data = try await sendBoardRequest(body: body, logLabel: "Deleting board")
        let response = try JSONDecoder().decode(UpdateBoardResponse.self, from: data)
        try await applyBoardUpdate(response, fallbackFrameId: frameId)
    }

    func reorderBoards(frameId: String, orders: [[String: Any]]) async throws {
        guard let projectId else {
            throw AuthError.noAuth
        }

        let body: [String: Any] = [
            "projectId": projectId,
            "frameId": frameId,
            "action": "reorder",
            "orders": orders
        ]

        let data = try await sendBoardRequest(body: body, logLabel: "Reordering boards")
        let response = try JSONDecoder().decode(UpdateBoardResponse.self, from: data)
        try await applyBoardUpdate(response, fallbackFrameId: frameId)
    }

    func pinBoard(frameId: String, boardId: String) async throws {
        guard let projectId else {
            throw AuthError.noAuth
        }

        let body: [String: Any] = [
            "projectId": projectId,
            "frameId": frameId,
            "action": "pin",
            "boardId": boardId
        ]

        let data = try await sendBoardRequest(body: body, logLabel: "Pinning board")
        let response = try JSONDecoder().decode(UpdateBoardResponse.self, from: data)
        try await applyBoardUpdate(response, fallbackFrameId: frameId)
    }

    func removeBoardImage(frameId: String, boardLabel: String) async throws {
        guard let projectId else {
            throw AuthError.noAuth
        }

        let body: [String: Any] = [
            "projectId": projectId,
            "frameId": frameId,
            "board": boardLabel
        ]

        let data = try await sendBoardRequest(for: .removeImage, body: body, logLabel: "Removing board image")
        let response = try JSONDecoder().decode(BasicResponse.self, from: data)
        guard response.success else {
            throw AuthError.authenticationFailedWithMessage(response.error ?? "Failed to remove board image")
        }
        try await fetchFrames()
    }

    private func sendBoardRequest(
        for endpoint: APIEndpoint = .updateBoard,
        body: [String: Any],
        logLabel: String
    ) async throws -> Data {
        var request = try authorizedRequest(for: endpoint, body: body)

        let requestJSON = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "Unable to encode"
        print("📤 \(logLabel)...")
        print("🔗 URL: \(request.url?.absoluteString ?? "unknown")")
        print("📝 Request body: \(requestJSON)")

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Failed to update board - Status: \(httpResponse.statusCode)")
            print("📝 Response: \(errorBody)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                logout()
                throw AuthError.unauthorized
            }
            throw AuthError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let responseJSON = String(data: data, encoding: .utf8) ?? "Unable to decode"
        print("📥 Board response received (\(httpResponse.statusCode)):")
        print(responseJSON)

        return data
    }

    private func applyBoardUpdate(_ response: UpdateBoardResponse, fallbackFrameId: String) async throws {
        guard response.success else {
            throw AuthError.authenticationFailedWithMessage(response.error ?? "Failed to update board")
        }

        guard let boards = response.boards else {
            try await fetchFrames()
            return
        }

        let frameId = response.resolvedId ?? fallbackFrameId
        guard let index = frames.firstIndex(where: { $0.id == frameId }) else { return }

        let mainBoardType = response.mainBoardType ?? frames[index].mainBoardType
        frames[index] = frames[index].updatingBoards(boards, mainBoardType: mainBoardType)

        if let projectId {
            cacheFrames(frames, for: projectId)
        }
    }

    // Logout and clear auth data
    func logout() {
        let cachedProjectId = projectId
        UserDefaults.standard.removeObject(forKey: projectIdKey)
        UserDefaults.standard.removeObject(forKey: projectTitleKey)
        UserDefaults.standard.removeObject(forKey: accessCodeKey)
        UserDefaults.standard.removeObject(forKey: tokenHashKey)
        if let cachedProjectId {
            UserDefaults.standard.removeObject(forKey: cachedCreativesKey(for: cachedProjectId))
            UserDefaults.standard.removeObject(forKey: cachedFramesKey(for: cachedProjectId))
        }
        self.projectId = nil
        self.projectTitle = nil
        self.accessCode = nil
        self.token = nil
        self.isAuthenticated = false
        self.creatives = []
        self.projectDetails = nil
        self.frames = []
        self.isScheduleActive = false
        self.cachedSchedule = nil
        self.fetchedSchedules = []
    }

    private func cachedCreativesKey(for projectId: String) -> String {
        "\(cachedCreativesKeyPrefix)\(projectId)"
    }

    private func cachedFramesKey(for projectId: String) -> String {
        "\(cachedFramesKeyPrefix)\(projectId)"
    }

    private func loadCachedProjectData(for projectId: String) {
        if creatives.isEmpty, let cached = loadCachedCreatives(for: projectId) {
            creatives = cached
        }

        if frames.isEmpty, let cached = loadCachedFrames(for: projectId) {
            frames = cached
        }
    }

    private func loadCachedCreatives(for projectId: String) -> [Creative]? {
        guard let data = UserDefaults.standard.data(forKey: cachedCreativesKey(for: projectId)) else {
            return nil
        }

        do {
            return try JSONDecoder().decode([Creative].self, from: data)
        } catch {
            print("❌ Failed to decode cached creatives: \(error)")
            return nil
        }
    }

    private func loadCachedFrames(for projectId: String) -> [Frame]? {
        guard let data = UserDefaults.standard.data(forKey: cachedFramesKey(for: projectId)) else {
            return nil
        }

        do {
            return try JSONDecoder().decode([Frame].self, from: data)
        } catch {
            print("❌ Failed to decode cached frames: \(error)")
            return nil
        }
    }

    private func cacheCreatives(_ creatives: [Creative], for projectId: String) {
        do {
            let data = try JSONEncoder().encode(creatives)
            UserDefaults.standard.set(data, forKey: cachedCreativesKey(for: projectId))
        } catch {
            print("❌ Failed to cache creatives: \(error)")
        }
    }

    private func cacheFrames(_ frames: [Frame], for projectId: String) {
        do {
            let data = try JSONEncoder().encode(frames)
            UserDefaults.standard.set(data, forKey: cachedFramesKey(for: projectId))
        } catch {
            print("❌ Failed to cache frames: \(error)")
        }
    }

    // MARK: - Schedule Fetching

    func cachedSchedule(for scheduleId: String) -> ProjectSchedule? {
        if let inMemory = fetchedSchedules.first(where: { $0.id == scheduleId }) {
            return inMemory
        }

        if let cachedSchedule, cachedSchedule.id == scheduleId {
            return cachedSchedule
        }

        if let stored = scheduleCache.cachedSchedule(withId: scheduleId) {
            cachedSchedule = stored
            fetchedSchedules.append(stored)
            return stored
        }

        return nil
    }

    func clearCachedSchedules(keeping scheduleId: String?) {
        if cachedSchedule?.id != scheduleId {
            cachedSchedule = nil
        }

        fetchedSchedules.removeAll { $0.id != scheduleId }
        scheduleCache.clear(exceptId: scheduleId)
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            let response = try await URLSession.shared.data(for: request)
            connectionMonitor?.registerNetworkSuccess()
            return response
        } catch {
            connectionMonitor?.registerImmediateFailure(for: error)
            throw error
        }
    }

    func fetchSchedule(for scheduleId: String) async throws -> ProjectSchedule {
        let body: [String: Any] = [
            "scheduleId": scheduleId
        ]

        var request = try authorizedRequest(for: .schedule, body: body)

        let requestJSON = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "Unable to encode"
        print("📤 Fetching schedule...")
        print("🔗 URL: \(request.url?.absoluteString ?? "unknown")")
        print("📝 Request body: \(requestJSON)")

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Failed to fetch schedule - Status: \(httpResponse.statusCode)")
            print("📝 Response: \(errorBody)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                logout()
                throw AuthError.unauthorized
            }
            throw AuthError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let responseJSON = String(data: data, encoding: .utf8) ?? "Unable to decode"
        print("📥 Schedule response received (\(httpResponse.statusCode)):")
        print(responseJSON)

        let decoder = JSONDecoder()
        let scheduleResponse = try decoder.decode(ScheduleFetchResponse.self, from: data)

        if scheduleResponse.success == false,
           (scheduleResponse.schedule?.isEmpty ?? true),
           (scheduleResponse.schedules?.isEmpty ?? true) {
            let message = scheduleResponse.error ?? "Failed to fetch schedule"
            print("❌ Schedule response failed: \(message)")
            throw AuthError.authenticationFailedWithMessage(message)
        }

        let availableSchedules: [ProjectSchedule]
        if let schedules = scheduleResponse.schedules, !schedules.isEmpty {
            availableSchedules = schedules
        } else if let schedule = scheduleResponse.schedule, !schedule.isEmpty {
            availableSchedules = schedule
        } else {
            availableSchedules = []
        }

        fetchedSchedules = availableSchedules

        let resolvedSchedule = availableSchedules.first { $0.id == scheduleId }
            ?? availableSchedules.first

        guard let schedule = resolvedSchedule else {
            let message = scheduleResponse.error ?? "Failed to fetch schedule"
            print("❌ Schedule response missing schedule: \(message)")
            throw AuthError.authenticationFailedWithMessage(message)
        }

        cachedSchedule = schedule
        scheduleCache.store(schedule: schedule)

        print("✅ Successfully fetched schedule \(schedule.id)")
        return schedule
    }
}

// MARK: - Models

struct AuthResponse: Codable {
    @SafeBool var success: Bool
    let message: String?
    let error: String?
    let token: String?
    let projectTitle: String?

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case error
        case token = "token"
        case projectTitle = "project_title"
    }
}

struct AuthErrorResponse: Codable {
    @SafeBool var success: Bool
    let error: String
}

struct DebugInfo {
    let requestURL: String
    let requestBody: String
    let responseStatusCode: Int
    let responseBody: String
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noAuth
    case unauthorized
    case invalidQRCode
    case missingAccessCode
    case authenticationFailed(statusCode: Int)
    case authenticationFailedWithMessage(String)
    case requestFailed(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .noAuth:
            return "No authentication data found. Please login."
        case .unauthorized:
            return "Authentication expired. Please login again."
        case .invalidQRCode:
            return "Not a valid Martini QR code. Please scan a QR code with projectId and accessCode parameters."
        case .missingAccessCode:
            return "Please enter the 4-digit access code."
        case .authenticationFailed(let code):
            return "Authentication failed with status code: \(code)"
        case .authenticationFailedWithMessage(let message):
            return message
        case .requestFailed(let code):
            return "Request failed with status code: \(code)"
        }
    }
}
