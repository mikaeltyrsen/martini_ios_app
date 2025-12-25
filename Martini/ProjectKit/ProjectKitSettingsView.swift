import SwiftUI

struct ProjectKitSettingsView: View {
    @EnvironmentObject private var authService: AuthService
    @StateObject private var store = ProjectKitStore()

    var body: some View {
        Group {
            Section("Scout Camera") {
                Text("Manage the cameras and lenses available in your scout kit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Cameras") {
                if store.selectedCameras().isEmpty {
                    Text("No cameras added yet.")
                        .foregroundStyle(.secondary)
                } else {
                    let selected = store.selectedCameras()
                    ForEach(selected) { camera in
                        VStack(alignment: .leading) {
                            Text("\(camera.brand) \(camera.model)")
                            Text("Sensor \(camera.sensorWidthMm, specifier: "%.2f") × \(camera.sensorHeightMm, specifier: "%.2f") mm")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        removeCameras(at: indexSet, from: selected)
                    }
                }

                NavigationLink {
                    ProjectKitCameraSelectionView(store: store)
                        .environmentObject(authService)
                } label: {
                    Label("Add Camera", systemImage: "plus")
                }
            }

            Section("Lenses") {
                if store.selectedLenses().isEmpty {
                    Text("No lenses added yet.")
                        .foregroundStyle(.secondary)
                } else {
                    let selected = store.selectedLenses()
                    ForEach(selected) { lens in
                        VStack(alignment: .leading) {
                            Text("\(lens.brand) \(lens.series)")
                            Text(lensLabel(for: lens))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        removeLenses(at: indexSet, from: selected)
                    }
                }

                NavigationLink {
                    ProjectKitLensSelectionView(store: store)
                        .environmentObject(authService)
                } label: {
                    Label("Add Lens", systemImage: "plus")
                }
            }
        }
        .onAppear {
            store.load(for: authService.projectId)
        }
        .onChange(of: authService.projectId) { _ in
            store.load(for: authService.projectId)
        }
    }

    private func lensLabel(for lens: DBLens) -> String {
        if lens.isZoom {
            return "\(Int(lens.focalLengthMinMm))–\(Int(lens.focalLengthMaxMm))mm T\(lens.tStop)"
        }
        return "\(Int(lens.focalLengthMinMm))mm T\(lens.tStop)"
    }

    private func removeCameras(at offsets: IndexSet, from cameras: [DBCamera]) {
        for index in offsets {
            let camera = cameras[index]
            store.removeCamera(id: camera.id, projectId: authService.projectId)
        }
    }

    private func removeLenses(at offsets: IndexSet, from lenses: [DBLens]) {
        for index in offsets {
            let lens = lenses[index]
            store.removeLens(id: lens.id, projectId: authService.projectId)
        }
    }
}
