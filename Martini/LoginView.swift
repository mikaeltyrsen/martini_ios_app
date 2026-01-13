//
//  LoginView.swift
//  Martini
//
//  Login screen with QR code scanning
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var nearbySignInService: NearbySignInService
    @Environment(\.colorScheme) private var colorScheme
    @State private var showScanner = false
    @State private var isAuthenticating = false
    @State private var scannedQRCode = ""
    @State private var showSavedProjects = false
    @State private var showSignInFailureAlert = false

    private var gradientColor: Color {
        colorScheme == .dark ? .black : .white
    }
    
    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground)
                .ignoresSafeArea()
            ParallaxBoardBackground()
                .opacity(colorScheme == .dark ? 1.0 : 1.0)
                .edgesIgnoringSafeArea(.all)

//            Color(.systemBackground)
//                .opacity(0.4)
//                .edgesIgnoringSafeArea(.all)
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: gradientColor.opacity(1.0), location: 0.0),   // top 100%
                    .init(color: gradientColor.opacity(0.0), location: 0.5),   // middle 0%
                    .init(color: gradientColor.opacity(1.0), location: 1.0)    // bottom 100%
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                // Logo/Title area
                VStack(spacing: 20) {
                    Image("martini-logo")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(.primary)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 240, height: 120)
                    
                    Text("Digital Storyboarding")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 80)
                
                Spacer()
                
                // Main action button
                VStack(spacing: 20) {
                    if isAuthenticating {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding()
                        
                        Text("Connecting...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    } else {
                        Button {
                            showScanner = true
                        } label: {
                            HStack {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.title2)
                                Text("SCAN CODE")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: 300)
                            .padding()
                            .background(Color.colorAccent)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 40)

                        Button {
                            showSavedProjects = true
                        } label: {
                            HStack {
                                Image(systemName: "photo.stack")
                                    .font(.title2)
                                Text("SELECT PROJECT")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: 300)
                            .padding()
                            .background(Color(.systemGray6))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 40)
                    }

                    if !isAuthenticating {
                        Text(nearbySignInService.guestStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .transition(.opacity)
                    }
                }
                
                // Footer
//                Text("Scan a QR code to access your Martini project")
//                    .font(.caption)
//                    .foregroundColor(.secondary)
//                    .multilineTextAlignment(.center)
//                    .padding(.horizontal)
//                    .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showScanner) {
            QRScannerView { qrCode in
                handleQRCode(qrCode)
            }
        }
        .sheet(isPresented: $showSavedProjects) {
            SavedProjectsSheet(onSelect: { project in
                handleSavedProjectSelection(project)
            })
            .environmentObject(authService)
        }
        .alert("Sign in failed", isPresented: $showSignInFailureAlert) {
            Button("OK", role: .cancel) {}
        }
        .onAppear {
            processPendingDeepLinkIfNeeded()
            nearbySignInService.startBrowsing()
        }
        .onDisappear {
            nearbySignInService.stopBrowsing()
        }
        .onChange(of: authService.isAuthenticated) { isAuthenticated in
            if isAuthenticated {
                nearbySignInService.stopBrowsing()
            } else {
                nearbySignInService.startBrowsing()
            }
        }
        .onChange(of: authService.pendingDeepLink) { _ in
            processPendingDeepLinkIfNeeded()
        }
        .onChange(of: nearbySignInService.approval) { approval in
            guard let approval else { return }
            handleNearbyApproval(approval)
        }
    }
    
    private func handleQRCode(_ qrCode: String) {
        scannedQRCode = qrCode
        isAuthenticating = true
        
        // Proceed directly to authentication
        checkAndProceedWithAuthentication()
    }

    private func handleSavedProjectSelection(_ project: StoredProject) {
        showSavedProjects = false
        scannedQRCode = "\(project.projectId)-\(project.accessCode)"
        isAuthenticating = true

        Task {
            do {
                try await authService.authenticate(withQRCode: scannedQRCode)
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    showSignInFailureAlert = true
                }

                if shouldMarkProjectExpired(for: error) {
                    await MainActor.run {
                        authService.markStoredProjectExpired(projectId: project.projectId)
                    }
                }
            }
        }
    }

    private func processPendingDeepLinkIfNeeded() {
        guard let pendingLink = authService.pendingDeepLink else { return }

        authService.pendingDeepLink = nil
        startAuthenticationFlow(with: pendingLink)
    }

    private func checkAndProceedWithAuthentication() {
        // Check if we need to prompt for access code
        do {
            let (accessCode, projectId) = try authService.parseQRCode(scannedQRCode)
            
            if accessCode == nil {
                isAuthenticating = false
                showSignInFailureAlert = true
            } else {
                // Already have access code, proceed
                proceedWithAuthentication(accessCode: nil)
            }
        } catch {
            isAuthenticating = false
            showSignInFailureAlert = true
        }
    }

    private func startAuthenticationFlow(with link: String) {
        scannedQRCode = link
        isAuthenticating = true
        checkAndProceedWithAuthentication()
    }

    private func handleNearbyApproval(_ approval: NearbySignInApproval) {
        nearbySignInService.stopBrowsing()
        nearbySignInService.clearApproval()
        let syntheticQRCode = "\(approval.projectId)-\(approval.projectCode)"
        startAuthenticationFlow(with: syntheticQRCode)
    }

    private func proceedWithAuthentication(accessCode: String?) {
        Task {
            do {
                try await authService.authenticate(withQRCode: scannedQRCode, manualAccessCode: accessCode)
                // Authentication successful - authService.isAuthenticated will trigger view change
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    showSignInFailureAlert = true
                }
            }
        }
    }

    private func shouldMarkProjectExpired(for error: Error) -> Bool {
        guard let authError = error as? AuthError else {
            return false
        }

        switch authError {
        case .authenticationFailed, .authenticationFailedWithMessage:
            return true
        default:
            return false
        }
    }
}

// MARK: - Parallax Board Background

struct ParallaxBoardBackground: View {
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let speed: CGFloat
    let amount: Int

    private struct BoardItem: Identifiable {
        let id = UUID()
        let imageName: String
        let size: CGSize
        let xFraction: CGFloat
        let speed: CGFloat
        let phase: CGFloat
        let spacing: CGFloat
        let status: FrameStatus
        let depth: CGFloat
    }

    @State private var items: [BoardItem]
    @State private var startDate = Date()

    init(
        minWidth: CGFloat = 80,
        maxWidth: CGFloat = 140,
        speed: CGFloat = 42,
        amount: Int = 10
    ) {
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.speed = speed
        self.amount = amount
        _items = State(initialValue: Self.makeItems(
            minWidth: minWidth,
            maxWidth: maxWidth,
            speed: speed,
            amount: amount
        ))
    }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSince(startDate)

                ZStack {
                    ForEach(items) { item in
                        let pathLength = proxy.size.height + item.size.height + item.spacing
                        let offset = (CGFloat(elapsed) * item.speed + item.phase * pathLength)
                            .truncatingRemainder(dividingBy: pathLength)
                        let yPosition = proxy.size.height + item.size.height - offset

                        BoardCardView(imageName: item.imageName, status: item.status)
                            .frame(width: item.size.width, height: item.size.height)
                            .position(x: proxy.size.width * item.xFraction, y: yPosition)
                            //.opacity(0.25 + item.depth * 0.6)
                            .zIndex(item.depth)
                            //.opacity(0.45)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private static func makeItems(
        minWidth: CGFloat,
        maxWidth: CGFloat,
        speed: CGFloat,
        amount: Int
    ) -> [BoardItem] {
        let imageNames = (1...17).map { String(format: "MartiniBoard%02d", $0) }
        let itemCount = max(amount, 1)
        var statuses = (0..<itemCount).map { index in
            weightedStatus(seed: index)
        }

        if !statuses.contains(.here) {
            statuses[max(0, itemCount - 1)] = .here
        }

        return (0..<itemCount).map { index in
            let widthRange = max(maxWidth - minWidth, 1)
            let width = CGFloat.random(in: minWidth...maxWidth)
            let aspectRatio = CGFloat.random(in: 1.4...1.8)
            let height = width / aspectRatio
            let depth = (width - minWidth) / widthRange
            let computedSpeed = (0.2 + 0.8 * depth) * speed
            let spacing = CGFloat.random(in: 140...260)
            return BoardItem(
                imageName: imageNames[index % imageNames.count],
                size: CGSize(width: width, height: height),
                xFraction: CGFloat.random(in: 0.12...0.88),
                speed: computedSpeed,
                phase: CGFloat.random(in: 0...1),
                spacing: spacing,
                status: statuses[index],
                depth: depth
            )
        }
    }

    private static func weightedStatus(seed: Int) -> FrameStatus {
        var generator = SeededRandomNumberGenerator(seed: UInt64(seed))
        let value = Double.random(in: 0...1, using: &generator)

        switch value {
        case 0..<0.5:
            return .done
//        case 0.6..<0.7:
//            return .here
//        case 0.7..<0.8:
//            return .next
//        case 0.8..<0.9:
//            return .omit
        default:
            return .none
        }
    }
}

struct BoardCardView: View {
    let imageName: String
    let status: FrameStatus

    var body: some View {
        ZStack {
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
                .shadow(color: Color.black.opacity(1), radius: 20, x: 0, y: 4)

            if status == .omit {
//                RoundedRectangle(cornerRadius: 8)
//                    .fill(Color.red.opacity(0.18))
            }

            if status == .done {
                DoneCrossOverlay()
            }
        }
    }

    private var borderWidth: CGFloat {
        switch status {
        case .here, .next, .done:
            return 3
        default:
            return 0
        }
    }

    private var borderColor: Color {
        switch status {
        case .here:
            return Color("MarkerHere")
        case .next:
            return Color("MarkerNext")
        case .done:
            return Color("MarkerDone")
        case .omit:
            return Color("MarkerDone")
        case .none:
            return .clear
        }
    }
}

struct DoneCrossOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
            }
            .stroke(Color.red.opacity(1), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            Path { path in
                path.move(to: CGPoint(x: proxy.size.width, y: 0))
                path.addLine(to: CGPoint(x: 0, y: proxy.size.height))
            }
            .stroke(Color.red.opacity(1), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

// MARK: - Project ID Entry View

struct ProjectIdEntryView: View {
    @Binding var projectId: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image("martini-logo")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundColor(.white)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 160, height: 80)
                    .padding(.top, 32)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Enter Project ID")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Type the project ID to log in without scanning a code.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("019b000a-02e9-7abe-911d-e83787fa9d2c", text: $projectId)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }
                .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        onSubmit(projectId)
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.colorAccent)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    Button("Cancel") {
                        onCancel()
                    }
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        onCancel()
                    }
                }
            }
        }
    }
}

// MARK: - Saved Projects Sheet

struct SavedProjectsSheet: View {
    @EnvironmentObject var authService: AuthService
    let onSelect: (StoredProject) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if authService.savedProjects.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "folder")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("No saved projects yet")
                            .font(.headline)

                        Text("Sign in successfully and your project will appear here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                } else {
                    List {
                        ForEach(authService.savedProjects) { project in
                            Button {
                                onSelect(project)
                            } label: {
                                HStack(spacing: 12) {
                                    Text(project.projectName)
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    if project.isExpired {
                                        Text("Expired")
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(Color.red.opacity(0.2)))
                                            .foregroundColor(.red)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: authService.removeStoredProjects)
                    }
                    .listStyle(.insetGrouped)
                    .padding(.top, 12)
                }
            }
            .navigationTitle("Select Project")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthService())
}
