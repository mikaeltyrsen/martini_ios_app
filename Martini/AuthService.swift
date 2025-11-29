//
//  AuthService.swift
//  Martini
//
//  Authentication service for managing login tokens
//

import Foundation

@MainActor
class AuthService: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var projectId: String?
    @Published var accessCode: String?
    @Published var tokenHash: String?
    @Published var bearerTokenOverride: String?
    @Published var debugInfo: DebugInfo?
    @Published var creatives: [Creative] = []
    @Published var isLoadingCreatives: Bool = false
    @Published var frames: [Frame] = []
    @Published var isLoadingFrames: Bool = false
    
    private let tokenHashKey = "martini_token_hash"
    private let projectIdKey = "martini_project_id"
    private let accessCodeKey = "martini_access_code"
    private let baseScriptsURL = "https://dev.shoot.nucontext.com/scripts/"

    init() {
        loadAuthData()
    }

    private enum APIEndpoint: String {
        case authLive = "auth/live.php"
        case creatives = "creatives/get_creatives.php"
        case frames = "frames/get.php"

        var path: String { rawValue }
    }

    private func url(for endpoint: APIEndpoint) throws -> URL {
        guard let url = URL(string: "\(baseScriptsURL)\(endpoint.path)") else {
            throw AuthError.invalidURL
        }
        return url
    }

    private func currentBearerToken() -> String? {
        if let override = bearerTokenOverride, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override
        }
        return tokenHash
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
           let tokenHash = UserDefaults.standard.string(forKey: tokenHashKey) {
            self.projectId = projectId
            self.accessCode = UserDefaults.standard.string(forKey: accessCodeKey)
            self.tokenHash = tokenHash
            self.isAuthenticated = true

            // Automatically refresh creatives when a token is already stored
            Task {
                try? await self.fetchCreatives()
            }
        }
    }

    // Save auth data to UserDefaults
    private func saveAuthData(projectId: String, accessCode: String, tokenHash: String) {
        UserDefaults.standard.set(projectId, forKey: projectIdKey)
        UserDefaults.standard.set(accessCode, forKey: accessCodeKey)
        UserDefaults.standard.set(tokenHash, forKey: tokenHashKey)
        self.projectId = projectId
        self.accessCode = accessCode
        self.tokenHash = tokenHash
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
            (data, response) = try await URLSession.shared.data(for: request)
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
        guard let tokenHash = authResponse.tokenHash else {
            throw AuthError.invalidResponse
        }

        print("🔑 Received token hash: \(tokenHash.prefix(20))...")

        // Save auth data (project ID, access code, and token hash)
        saveAuthData(projectId: projectId, accessCode: accessCode, tokenHash: tokenHash)
        
        print("💾 Saved auth data - projectId: \(projectId)")
        print("🎬 About to fetch creatives...")
        
        // Fetch creatives after successful authentication
        do {
            try await fetchCreatives()
        } catch {
            print("❌ Failed to fetch creatives: \(error)")
            throw error
        }
    }
    
    // Parse QR code URL and extract project ID, and optionally access code
    // Format: https://trymartini.com/*/####-####-####-#### (needs manual code entry)
    //     or: https://trymartini.com/*/####-####-####-####-#### (code included)
    func parseQRCode(_ qrCode: String) throws -> (accessCode: String?, projectId: String) {
        print("🔍 Parsing QR code: \(qrCode)")
        
        // Try to match 5 segments first (####-####-####-####-####)
        let pattern5 = "([0-9a-zA-Z]{4})-([0-9a-zA-Z]{4})-([0-9a-zA-Z]{4})-([0-9a-zA-Z]{4})-([0-9a-zA-Z]{4})"
        let regex5 = try NSRegularExpression(pattern: pattern5)
        let nsString = qrCode as NSString

        if let match = regex5.firstMatch(in: qrCode, range: NSRange(location: 0, length: nsString.length)) {
            // Extract all 5 segments
            var segments: [String] = []
            for i in 1...5 {
                let range = match.range(at: i)
                if range.location != NSNotFound {
                    segments.append(nsString.substring(with: range))
                }
            }
            
            print("🔍 Found 5 segments: \(segments)")
            
            if segments.count == 5 {
                // First 4 segments form the project ID, last segment is access code
                let projectId = segments[0..<4].joined(separator: "-")
                let accessCode = segments[4]
                print("🔍 Extracted - projectId: \(projectId), accessCode: \(accessCode)")
                return (accessCode, projectId)
            }
        }
        
        // Try to match 4 segments (####-####-####-####)
        let pattern4 = "([0-9a-zA-Z]{4})-([0-9a-zA-Z]{4})-([0-9a-zA-Z]{4})-([0-9a-zA-Z]{4})"
        let regex4 = try NSRegularExpression(pattern: pattern4)
        
        if let match = regex4.firstMatch(in: qrCode, range: NSRange(location: 0, length: nsString.length)) {
            // Extract all 4 segments
            var segments: [String] = []
            for i in 1...4 {
                let range = match.range(at: i)
                if range.location != NSNotFound {
                    segments.append(nsString.substring(with: range))
                }
            }
            
            print("🔍 Found 4 segments: \(segments)")
            
            if segments.count == 4 {
                // All 4 segments form the project ID, no access code
                let projectId = segments.joined(separator: "-")
                print("🔍 Extracted - projectId: \(projectId), accessCode: (needs manual entry)")
                return (nil, projectId)
            }
        }
        
        print("🔍 Could not find valid code pattern")
        throw AuthError.invalidQRCode
    }
    
    // Make authenticated API call
    func makeAuthenticatedRequest(to endpoint: APIEndpoint) async throws -> Data {
        guard projectId != nil else {
            throw AuthError.noAuth
        }

        let request = try authorizedRequest(for: endpoint, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)

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
    
    // Fetch creatives for the current project
    func fetchCreatives(pullAll: Bool = false) async throws {
        guard let projectId = projectId else {
            throw AuthError.noAuth
        }

        isLoadingCreatives = true
        defer { isLoadingCreatives = false }

        var body: [String: Any] = [
            "projectId": projectId,
            "pullAll": pullAll
        ]

        var request = try authorizedRequest(for: .creatives, body: body)

        let requestJSON = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "Unable to encode"
        print("📤 Fetching creatives...")
        print("🔗 URL: \(request.url?.absoluteString ?? "unknown")")
        print("📝 Request body: \(requestJSON)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
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
        
        let responseJSON = String(data: data, encoding: .utf8) ?? "Unable to decode"
        print("📥 Response received (\(httpResponse.statusCode)):")
        print(responseJSON)
        
        let decoder = JSONDecoder()
        let creativesResponse = try decoder.decode(CreativesResponse.self, from: data)
        
        guard creativesResponse.success else {
            print("❌ Creatives response failed: \(creativesResponse.error ?? "Unknown error")")
            throw AuthError.authenticationFailedWithMessage(creativesResponse.error ?? "Failed to fetch creatives")
        }
        
        self.creatives = creativesResponse.creatives
        print("✅ Successfully fetched \(creatives.count) creatives")
        for (index, creative) in creatives.prefix(3).enumerated() {
            print("  \(index + 1). \(creative.title) - \(creative.completedFrames)/\(creative.totalFrames) frames")
        }
        if creatives.count > 3 {
            print("  ... and \(creatives.count - 3) more")
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

        let (data, response) = try await URLSession.shared.data(for: request)

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

        let responseJSON = String(data: data, encoding: .utf8) ?? "Unable to decode"
        print("📥 Frames response received (\(httpResponse.statusCode)):")
        print(responseJSON)

        let decoder = JSONDecoder()
        let framesResponse = try decoder.decode(FramesResponse.self, from: data)

        guard framesResponse.success else {
            print("❌ Frames response failed: \(framesResponse.error ?? "Unknown error")")
            throw AuthError.authenticationFailedWithMessage(framesResponse.error ?? "Failed to fetch frames")
        }

        self.frames = framesResponse.frames
        print("✅ Successfully fetched \(frames.count) frames")
    }

    // Logout and clear auth data
    func logout() {
        UserDefaults.standard.removeObject(forKey: projectIdKey)
        UserDefaults.standard.removeObject(forKey: accessCodeKey)
        UserDefaults.standard.removeObject(forKey: tokenHashKey)
        self.projectId = nil
        self.accessCode = nil
        self.tokenHash = nil
        self.isAuthenticated = false
        self.creatives = []
        self.frames = []
    }
}

// MARK: - Models

struct AuthResponse: Codable {
    let success: Bool
    let message: String?
    let error: String?
    let tokenHash: String?

    enum CodingKeys: String, CodingKey {
        case success
        case message
        case error
        case tokenHash = "token_hash"
    }
}

struct AuthErrorResponse: Codable {
    let success: Bool
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
