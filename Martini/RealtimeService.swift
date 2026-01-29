import Foundation

/// Handles real-time server-sent events for Martini.
final class RealtimeService: NSObject, ObservableObject {
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var lastEventName: String?
    @Published private(set) var lastError: String?

    private let authService: AuthService
    private let websocketCalls: WebsocketCalls
    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var reconnectWorkItem: DispatchWorkItem?
    private var currentProjectId: String?
    private var cachedToken: String?

    private let reconnectDelay: TimeInterval = 2.0
    private let eventQueue = DispatchQueue(label: "com.martini.realtime")

    @MainActor
    init(authService: AuthService) {
        self.authService = authService
        self.websocketCalls = WebsocketCalls(authService: authService)
        super.init()

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 0
        configuration.timeoutIntervalForResource = 0
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    /// Synchronize the connection state with the current authentication status.
    func updateConnection(projectId: String?, isAuthenticated: Bool) {
        DispatchQueue.main.async {
            self.cachedToken = self.authService.currentBearerToken()
            if !isAuthenticated {
                self.disconnect()
                return
            }

            guard let projectId = projectId, !projectId.isEmpty else {
                self.disconnect()
                return
            }

            if projectId != self.currentProjectId {
                self.currentProjectId = projectId
                self.reconnect()
            } else {
                self.connectIfNeeded()
            }
        }
    }

    func disconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil

        task?.cancel()
        task = nil
        buffer = Data()

        DispatchQueue.main.async {
            self.isConnected = false
        }
    }

    // MARK: - Private helpers

    private func reconnect() {
        disconnect()
        scheduleReconnect()
    }

    private func connectIfNeeded() {
        guard task == nil else { return }
        guard let projectId = currentProjectId else { return }
        guard let url = AppEnvironment.realtimeProjectURL(projectId: projectId) else {
            DispatchQueue.main.async {
                self.lastError = "Invalid realtime URL"
            }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let token = cachedToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let dataTask = session.dataTask(with: request)
        task = dataTask
        dataTask.resume()
    }

    private func scheduleReconnect() {
        guard reconnectWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.reconnectWorkItem = nil
            self?.connectIfNeeded()
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + reconnectDelay, execute: workItem)
    }

    @MainActor
    private func handleEvent(name: String, dataString: String) {
        print("📡 Websocket event received: \(name) | data: \(dataString)")

        lastEventName = name

        if name == "connected" {
            isConnected = true
            return
        }

        websocketCalls.handle(event: name, dataString: dataString)
    }

    private func processEventChunk(_ chunk: Data) {
        guard let text = String(data: chunk, encoding: .utf8) else { return }

        var eventName = "message"
        var dataLines: [String] = []

        text.split(whereSeparator: \.isNewline).forEach { substring in
            let line = String(substring)
            if line.hasPrefix("event:") {
                eventName = line.replacingOccurrences(of: "event:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let value = line.replacingOccurrences(of: "data:", with: "").trimmingCharacters(in: .whitespaces)
                dataLines.append(value)
            }
        }

        let dataString = dataLines.joined(separator: "\n")

        DispatchQueue.main.async {
            self.handleEvent(name: eventName, dataString: dataString)
        }
    }
}

// MARK: - URLSessionDataDelegate

extension RealtimeService: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        eventQueue.async { [weak self] in
            guard let self else { return }
            self.buffer.append(data)

            let separator = Data("\n\n".utf8)

            while let range = self.buffer.range(of: separator) {
                let chunk = self.buffer.subdata(in: 0..<range.lowerBound)
                self.buffer.removeSubrange(0..<range.upperBound)
                self.processEventChunk(chunk)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.task = nil
            if let error {
                self.lastError = error.localizedDescription
            }
        }
        scheduleReconnect()
    }
}
