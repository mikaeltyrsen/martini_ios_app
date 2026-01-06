//
//  ConnectionMonitor.swift
//  Martini
//
//  Created by OpenAI.
//

import Foundation

@MainActor
final class ConnectionMonitor: ObservableObject {
    enum Status: Equatable {
        case online
        case unstable
        case offline
        case backOnline
    }

    @Published private(set) var status: Status = .online

    private let pingURL: URL
    private let pingInterval: TimeInterval = 8
    private let pingTimeout: TimeInterval = 7
    private var pingTask: Task<Void, Never>?
    private var backOnlineTask: Task<Void, Never>?
    private var consecutiveFailures: Int = 0

    var isOffline: Bool {
        status == .offline
    }

    init(pingURL: URL) {
        self.pingURL = pingURL
    }

    func updateConnection(isAuthenticated: Bool) {
        if isAuthenticated {
            startPingingIfNeeded()
        } else {
            stopPinging()
        }
    }

    func registerNetworkSuccess() {
        handleSuccess()
    }

    func registerImmediateFailure(for error: Error) {
        guard error.isConnectivityError else { return }
        registerImmediateFailure()
    }

    func registerImmediateFailure() {
        consecutiveFailures = 2
        setStatus(.offline)
    }

    private func startPingingIfNeeded() {
        guard pingTask == nil else { return }

        pingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.performPing()
                try? await Task.sleep(for: .seconds(self.pingInterval))
            }
        }
    }

    private func stopPinging() {
        pingTask?.cancel()
        pingTask = nil
        backOnlineTask?.cancel()
        backOnlineTask = nil
        consecutiveFailures = 0
        setStatus(.online)
    }

    private func performPing() async {
        var request = URLRequest(url: pingURL)
        request.timeoutInterval = pingTimeout

        do {
            _ = try await URLSession.shared.data(for: request)
            handleSuccess()
        } catch {
            handleFailure()
        }
    }

    private func handleSuccess() {
        consecutiveFailures = 0
        if status == .unstable || status == .offline {
            showBackOnline()
        }
    }

    private func handleFailure() {
        consecutiveFailures += 1
        if consecutiveFailures == 1 {
            setStatus(.unstable)
        } else {
            setStatus(.offline)
        }
    }

    private func showBackOnline() {
        setStatus(.backOnline)
        backOnlineTask?.cancel()
        backOnlineTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            await self?.setStatus(.online)
        }
    }

    private func setStatus(_ newStatus: Status) {
        backOnlineTask?.cancel()
        backOnlineTask = nil
        status = newStatus
    }
}

extension ConnectionMonitor: ConnectionMonitoring {}

private extension Error {
    var isConnectivityError: Bool {
        let nsError = self as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }

        switch nsError.code {
        case NSURLErrorNotConnectedToInternet,
             NSURLErrorTimedOut,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorDNSLookupFailed:
            return true
        default:
            return false
        }
    }
}
