//
//  QRScannerView.swift
//  Martini
//
//  QR code scanner using AVFoundation
//

import SwiftUI
import AVFoundation
#if os(iOS)
import AudioToolbox
#endif

struct QRScannerView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var scanner = QRScanner()
    let onCodeScanned: (String) -> Void
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            CameraPreview(session: scanner.captureSession)
                .edgesIgnoringSafeArea(.all)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Circle())
                    .accessibilityLabel("Close camera")
            }
            .padding(.top, 16)
            .padding(.leading, 16)
            
            VStack {
                Spacer()
                
                if scanner.permissionDenied {
                    VStack(spacing: 16) {
                        Text("Camera Access Required")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Please enable camera access in Settings")
                            .font(.subheadline)
                            .foregroundColor(.white)
                        Button("Open Settings") {
                            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsURL)
                            }
                        }
                        .foregroundColor(.martiniDefaultColor)
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(10)
                    .padding(.bottom, 50)
                } else {
                    Text("Scan QR Code")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                        .padding(.bottom, 50)
                }
            }
        }
        .onChange(of: scanner.scannedCode) { oldValue, newValue in
            if let code = newValue {
                onCodeScanned(code)
                dismiss()
            }
        }
        .onAppear {
            scanner.startScanning()
        }
        .onDisappear {
            scanner.stopScanning()
        }
    }
}

// MARK: - QR Scanner Controller

class QRScanner: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    @Published var scannedCode: String?
    @Published var permissionDenied = false
    @Published var captureSession: AVCaptureSession?
    
    func startScanning() {
        checkPermissions()
    }
    
    func stopScanning() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }
    
    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCamera()
                    } else {
                        self?.permissionDenied = true
                    }
                }
            }
        default:
            DispatchQueue.main.async { [weak self] in
                self?.permissionDenied = true
            }
        }
    }
    
    private func setupCamera() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let session = AVCaptureSession()
            session.beginConfiguration()
            
            guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
                print("Failed to get camera device")
                return
            }
            
            let videoInput: AVCaptureDeviceInput
            do {
                videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            } catch {
                print("Failed to create video input: \(error)")
                return
            }
            
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            } else {
                print("Could not add video input")
                return
            }
            
            let metadataOutput = AVCaptureMetadataOutput()
            
            if session.canAddOutput(metadataOutput) {
                session.addOutput(metadataOutput)
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.qr]
            } else {
                print("Could not add metadata output")
                return
            }
            
            session.commitConfiguration()
            
            DispatchQueue.main.async {
                self.captureSession = session
            }
            
            session.startRunning()
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            
#if os(iOS) && !targetEnvironment(macCatalyst)
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
#endif
            scannedCode = stringValue
            stopScanning()
        }
    }
}

// MARK: - Camera Preview

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession?
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Remove existing preview layers
        uiView.layer.sublayers?.forEach { layer in
            if layer is AVCaptureVideoPreviewLayer {
                layer.removeFromSuperlayer()
            }
        }
        
        // Add new preview layer if session exists
        if let session = session {
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.frame = uiView.bounds
            previewLayer.videoGravity = .resizeAspectFill
            uiView.layer.addSublayer(previewLayer)
        }
    }
}

#Preview {
    QRScannerView { code in
        print("Scanned: \(code)")
    }
}
