//
//  NearbySignInService.swift
//  Martini
//
//  MultipeerConnectivity helper for nearby sign-in.
//

import Foundation
import MultipeerConnectivity
import UIKit

struct NearbySignInApproval: Equatable {
    let projectId: String
    let projectCode: String
}

struct NearbySignInRequest: Identifiable, Equatable {
    let id = UUID()
    let peerID: MCPeerID

    var displayName: String {
        peerID.displayName
    }

    static func == (lhs: NearbySignInRequest, rhs: NearbySignInRequest) -> Bool {
        lhs.peerID == rhs.peerID
    }
}

@MainActor
final class NearbySignInService: NSObject, ObservableObject {
    enum Role {
        case host
        case guest
        case none
    }

    @Published var guestStatus: String = "Looking for nearby sign-in…"
    @Published var pendingRequest: NearbySignInRequest?
    @Published var approval: NearbySignInApproval?
    @Published private(set) var canHostSignInRequests: Bool = false

    private enum MessageType: String, Codable {
        case pairRequest
        case approved
        case denied
    }

    private struct Message: Codable {
        let type: MessageType
        let projectId: String?
        let projectCode: String?
    }

    private let serviceType = "martini-login"
    private let peerID = MCPeerID(displayName: UIDevice.current.name)
    private lazy var session: MCSession = {
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        return session
    }()

    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var role: Role = .none
    private var hostProjectId: String?
    private var hostProjectCode: String?
    private var invitedPeers = Set<String>()
    private var requestedPeers = Set<String>()

    private func log(_ message: String) {
        print("📡 Nearby sign-in: \(message)")
    }

    func startHosting(projectId: String, projectCode: String) {
        guard canHostSignInRequests else {
            log("Hosting blocked (no edit access)")
            return
        }
        hostProjectId = projectId
        hostProjectCode = projectCode
        guard role != .host else { return }
        stopBrowsing()
        role = .host
        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: ["role": "host"], serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        log("Hosting started as \(peerID.displayName) (\(serviceType))")
    }

    func stopHosting() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        if role == .host {
            role = .none
        }
        log("Hosting stopped")
    }

    func updateHostPermission(_ isAllowed: Bool) {
        guard canHostSignInRequests != isAllowed else { return }
        canHostSignInRequests = isAllowed
        if !isAllowed {
            pendingRequest = nil
            stopHosting()
        }
    }

    func startBrowsing() {
        guard role != .guest else { return }
        stopHosting()
        role = .guest
        invitedPeers.removeAll()
        requestedPeers.removeAll()
        guestStatus = "Looking for nearby sign-in…"
        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        log("Browsing started as \(peerID.displayName) (\(serviceType))")
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        if role == .guest {
            role = .none
        }
        log("Browsing stopped")
    }

    func clearApproval() {
        approval = nil
    }

    func approvePendingRequest() {
        guard let pendingRequest, let projectId = hostProjectId, let projectCode = hostProjectCode else { return }
        let message = Message(type: .approved, projectId: projectId, projectCode: projectCode)
        send(message, to: pendingRequest.peerID)
        self.pendingRequest = nil
        log("Approved request from \(pendingRequest.displayName)")
    }

    func denyPendingRequest() {
        guard let pendingRequest else { return }
        let message = Message(type: .denied, projectId: nil, projectCode: nil)
        send(message, to: pendingRequest.peerID)
        self.pendingRequest = nil
        log("Denied request from \(pendingRequest.displayName)")
    }

    private func send(_ message: Message, to peer: MCPeerID) {
        guard session.connectedPeers.contains(peer) else {
            log("Send blocked to \(peer.displayName) (not connected)")
            return
        }
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: [peer], with: .reliable)
            log("Sent \(message.type.rawValue) to \(peer.displayName)")
        } catch {
            print("❌ Nearby sign-in send failed: \(error)")
        }
    }
}

extension NearbySignInService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        Task { @MainActor in
            guard role == .host else {
                invitationHandler(false, nil)
                return
            }
            log("Received invitation from \(peerID.displayName)")
            invitationHandler(true, session)
        }
    }
}

extension NearbySignInService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        Task { @MainActor in
            guard role == .guest else { return }
            guard !invitedPeers.contains(peerID.displayName) else { return }
            invitedPeers.insert(peerID.displayName)
            log("Found peer \(peerID.displayName); sending invite")
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            invitedPeers.remove(peerID.displayName)
            log("Lost peer \(peerID.displayName)")
        }
    }

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error
    ) {
        Task { @MainActor in
            guestStatus = "Looking for nearby sign-in…"
            print("❌ Nearby sign-in browse failed: \(error)")
        }
    }
}

extension NearbySignInService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            guard role == .guest else { return }
            let stateDescription: String
            switch state {
            case .notConnected:
                stateDescription = "not connected"
            case .connecting:
                stateDescription = "connecting"
            case .connected:
                stateDescription = "connected"
            @unknown default:
                stateDescription = "unknown"
            }
            log("Session state with \(peerID.displayName): \(stateDescription)")
            guard state == .connected else { return }
            guard !requestedPeers.contains(peerID.displayName) else { return }
            requestedPeers.insert(peerID.displayName)
            guestStatus = "Request sent…"
            log("Connected to \(peerID.displayName); sending pair request")
            let message = Message(type: .pairRequest, projectId: nil, projectCode: nil)
            send(message, to: peerID)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            do {
                let message = try JSONDecoder().decode(Message.self, from: data)
                switch message.type {
                case .pairRequest:
                    guard role == .host else { return }
                    guard canHostSignInRequests else {
                        let message = Message(type: .denied, projectId: nil, projectCode: nil)
                        send(message, to: peerID)
                        log("Denied pair request from \(peerID.displayName) (no edit access)")
                        return
                    }
                    pendingRequest = NearbySignInRequest(peerID: peerID)
                    log("Received pair request from \(peerID.displayName)")
                case .approved:
                    guard role == .guest,
                          let projectId = message.projectId,
                          let projectCode = message.projectCode else { return }
                    approval = NearbySignInApproval(projectId: projectId, projectCode: projectCode)
                    guestStatus = "Signing in…"
                    log("Received approval from \(peerID.displayName)")
                case .denied:
                    guard role == .guest else { return }
                    guestStatus = "Request declined."
                    log("Received denial from \(peerID.displayName)")
                }
            } catch {
                print("❌ Nearby sign-in decode failed: \(error)")
            }
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}

extension NearbySignInService {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        Task { @MainActor in
            print("❌ Nearby sign-in advertise failed: \(error)")
        }
    }
}
