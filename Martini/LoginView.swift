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
    
    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground)
                .edgesIgnoringSafeArea(.all)
            
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
    }
    
    private func handleQRCode(_ qrCode: String) {
        scannedQRCode = qrCode
        isAuthenticating = true
        errorMessage = nil
        
        // Proceed directly to authentication
        checkAndProceedWithAuthentication()
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
