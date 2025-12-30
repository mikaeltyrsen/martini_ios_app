//
//  LoginView.swift
//  Martini
//
//  Login screen with QR code scanning
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    @State private var showScanner = false
    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var scannedQRCode = ""
    @State private var showAccessCodeEntry = false
    @State private var scannedProjectId = ""
    @State private var showProjectIdEntry = false
    @State private var projectIdInput = ""
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
            ParallaxBoardBackground()
                .edgesIgnoringSafeArea(.all)

//            Color(.systemBackground)
//                .opacity(0.4)
//                .edgesIgnoringSafeArea(.all)
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .black.opacity(1.0), location: 0.0),   // top 100%
                    .init(color: .black.opacity(0.0), location: 0.5),   // middle 0%
                    .init(color: .black.opacity(1.0), location: 1.0)    // bottom 100%
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            if showAccessCodeEntry {
                // Access code entry screen
                AccessCodeEntryViewContainer(
                    projectId: scannedProjectId,
                    errorMessage: errorMessage,
                    onSubmit: { code in
                        proceedWithAuthentication(accessCode: code)
                    },
                    onCancel: {
                        showAccessCodeEntry = false
                        isAuthenticating = false
                        errorMessage = nil
                    }
                )
            } else {
                VStack(spacing: 40) {
                    // Logo/Title area
                    VStack(spacing: 20) {
                        Image("martini-logo")
                            .resizable()
                            .renderingMode(.template)
                            .foregroundColor(.white)
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
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.colorAccent)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .padding(.horizontal, 40)

                            Button {
                                showProjectIdEntry = true
                                errorMessage = nil
                            } label: {
                                HStack {
                                    Image(systemName: "key.fill")
                                        .font(.title2)
                                    Text("LOGIN WITH PROJECT ID")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray6))
                                .foregroundColor(.primary)
                                .cornerRadius(12)
                            }
                            .padding(.horizontal, 40)
                        }
                        
                        // Error message
                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                    }
                    
                    // Footer
                    Text("Scan a QR code to access your Martini project")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                }
            }
        }
        .sheet(isPresented: $showScanner) {
            QRScannerView { qrCode in
                handleQRCode(qrCode)
            }
        }
        .sheet(isPresented: $showProjectIdEntry) {
            ProjectIdEntryView(projectId: $projectIdInput) { projectId in
                handleManualProjectId(projectId)
            } onCancel: {
                showProjectIdEntry = false
                projectIdInput = ""
            }
        }
        .onAppear {
            processPendingDeepLinkIfNeeded()
        }
        .onChange(of: authService.pendingDeepLink) { _ in
            processPendingDeepLinkIfNeeded()
        }
    }
    
    private func handleQRCode(_ qrCode: String) {
        scannedQRCode = qrCode
        isAuthenticating = true
        errorMessage = nil
        
        // Proceed directly to authentication
        checkAndProceedWithAuthentication()
    }

    private func handleManualProjectId(_ projectId: String) {
        let trimmed = projectId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            errorMessage = "Please enter a valid project ID."
            return
        }

        scannedQRCode = trimmed
        isAuthenticating = true
        errorMessage = nil
        showProjectIdEntry = false

        checkAndProceedWithAuthentication()
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
            scannedProjectId = projectId
            
            if accessCode == nil {
                // Need to prompt for manual entry
                showAccessCodeEntry = true
            } else {
                // Already have access code, proceed
                proceedWithAuthentication(accessCode: nil)
            }
        } catch {
            errorMessage = error.localizedDescription
            isAuthenticating = false
        }
    }

    private func startAuthenticationFlow(with link: String) {
        scannedQRCode = link
        isAuthenticating = true
        errorMessage = nil
        showAccessCodeEntry = false
        showProjectIdEntry = false
        checkAndProceedWithAuthentication()
    }

    private func proceedWithAuthentication(accessCode: String?) {
        Task {
            do {
                try await authService.authenticate(withQRCode: scannedQRCode, manualAccessCode: accessCode)
                // Authentication successful - authService.isAuthenticated will trigger view change
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isAuthenticating = false
                }
            }
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

// MARK: - Access Code Entry View

struct AccessCodeEntryView: View {
    let projectId: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    
    @State private var code: [String] = ["", "", "", ""]
    @FocusState private var focusedField: Int?
    @State private var shakeOffset: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 40) {
            headerSection
            Spacer()
            codeInputSection
            Spacer()
            cancelButton
        }
        .onAppear {
            // Auto-focus first field immediately to show keyboard
            focusedField = 0
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 20) {
            Image("martini-logo")
                .resizable()
                .renderingMode(.template)
                .foregroundColor(.white)
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 60)
            
            Text("Enter Access Code")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Project: \(projectId)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 80)
    }
    
    private var codeInputSection: some View {
        HStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { index in
                codeField(at: index)
            }
        }
        .padding(.horizontal, 40)
        .offset(x: shakeOffset)
        .animation(.default, value: shakeOffset)
    }
    
    private func codeField(at index: Int) -> some View {
        CodeDigitField(
            text: $code[index],
            isFocused: focusedField == index
        )
        .focused($focusedField, equals: index)
        .onChange(of: code[index]) { oldValue, newValue in
            handleTextChange(at: index, oldValue: oldValue, newValue: newValue)
        }
        .onKeyPress(.delete) {
            // Handle backspace key specifically
            if code[index].isEmpty && index > 0 {
                // Current field is empty, delete previous
                code[index - 1] = ""
                focusedField = index - 1
                return .handled
            }
            return .ignored
        }
    }
    
    private var cancelButton: some View {
        Button("Cancel") {
            onCancel()
        }
        .font(.headline)
        .foregroundColor(.secondary)
        .padding(.bottom, 40)
    }
    
    private func handleTextChange(at index: Int, oldValue: String, newValue: String) {
        // Convert to uppercase
        let uppercased = newValue.uppercased()
        
        // Check if text was deleted (backspace pressed)
        if uppercased.isEmpty && !oldValue.isEmpty {
            // User pressed backspace - current field is now empty
            // Move to previous field
            if index > 0 {
                // Small delay to ensure state updates properly
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    focusedField = index - 1
                }
            }
            return
        }
        
        // Take only the last character entered (handles paste/multi-char input)
        let filtered = String(uppercased.suffix(1))
        
        // Update the value only if it changed
        if filtered != newValue {
            code[index] = filtered
        }
        
        // Move to next field if we have a character
        if !filtered.isEmpty && index < 3 {
            focusedField = index + 1
        }
        
        // Check if all 4 are filled
        if code.allSatisfy({ !$0.isEmpty }) {
            let fullCode = code.joined()
            // Auto-submit
            onSubmit(fullCode)
        }
    }
    
    func triggerErrorShake() {
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        
        // Shake animation
        withAnimation(.default) {
            shakeOffset = 10
        }
        withAnimation(.default.delay(0.1)) {
            shakeOffset = -10
        }
        withAnimation(.default.delay(0.2)) {
            shakeOffset = 10
        }
        withAnimation(.default.delay(0.3)) {
            shakeOffset = -10
        }
        withAnimation(.default.delay(0.4)) {
            shakeOffset = 0
        }
        
        // Clear the code after shake
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            code = ["", "", "", ""]
            focusedField = 0
        }
    }
}

// MARK: - Code Digit Field

struct CodeDigitField: View {
    @Binding var text: String
    let isFocused: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Invisible text field for cursor/keyboard
                TextField("", text: $text)
                    .font(.system(size: 40, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .keyboardType(.asciiCapable)
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
                    .frame(width: 60, height: 60)
                    .opacity(0.01) // Nearly invisible but still functional
                
                // Display text on top
                Text(text)
                    .font(.system(size: 40, weight: .semibold))
                    .frame(width: 60, height: 60)
                    .foregroundColor(.primary)
            }
            
            // Bottom line
            Rectangle()
                .fill(isFocused ? Color.colorAccent : Color.gray.opacity(0.5))
                .frame(height: 2)
        }
        .frame(width: 60)
    }
}

// MARK: - Container to handle error shake

struct AccessCodeEntryViewContainer: View {
    let projectId: String
    let errorMessage: String?
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    
    @State private var viewID = UUID()
    @State private var lastError: String?
    
    var body: some View {
        AccessCodeEntryView(
            projectId: projectId,
            onSubmit: onSubmit,
            onCancel: onCancel
        )
        .id(viewID)
        .onChange(of: errorMessage) { oldValue, newValue in
            if let newValue = newValue, newValue != lastError {
                lastError = newValue
                // Trigger shake by recreating view
                viewID = UUID()
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthService())
}
