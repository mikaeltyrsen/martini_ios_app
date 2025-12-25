import SwiftUI

struct ProjectKitSettingsView: View {
    @EnvironmentObject private var authService: AuthService
    @StateObject private var store = ProjectKitStore()

    var body: some View {
        Section("Project Kit") {
            if store.availableCameras.isEmpty && store.availableLenses.isEmpty {
                Text("Loading kit…")
                    .foregroundStyle(.secondary)
            } else {
                cameraSection
                lensSection
            }
        }
        .onAppear {
            store.load(for: authService.projectId)
        }
        .onChange(of: authService.projectId) { _ in
            store.load(for: authService.projectId)
        }
    }

    private var cameraSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cameras")
                .font(.headline)
            ForEach(store.availableCameras) { camera in
                Toggle(isOn: Binding(
                    get: { store.selectedCameraIds.contains(camera.id) },
                    set: { _ in store.toggleCamera(camera, projectId: authService.projectId) }
                )) {
                    VStack(alignment: .leading) {
                        Text("\(camera.brand) \(camera.model)")
                        Text("Sensor \(camera.sensorWidthMm, specifier: "%.2f") × \(camera.sensorHeightMm, specifier: "%.2f") mm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var lensSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lenses")
                .font(.headline)
            ForEach(store.availableLenses) { lens in
                Toggle(isOn: Binding(
                    get: { store.selectedLensIds.contains(lens.id) },
                    set: { _ in store.toggleLens(lens, projectId: authService.projectId) }
                )) {
                    VStack(alignment: .leading) {
                        Text("\(lens.brand) \(lens.series)")
                        Text(lensLabel(for: lens))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func lensLabel(for lens: DBLens) -> String {
        if lens.isZoom {
            return "\(Int(lens.focalLengthMinMm))–\(Int(lens.focalLengthMaxMm))mm T\(lens.tStop)"
        }
        return "\(Int(lens.focalLengthMinMm))mm T\(lens.tStop)"
    }
}
