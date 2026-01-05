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
                let selected = store.selectedCameras()
                ForEach(selected) { camera in
                    VStack(alignment: .leading) {
                        Text("\(camera.brand) \(camera.model)")
                        Text(cameraSensorLabel(camera))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { indexSet in
                    removeCameras(at: indexSet, from: selected)
                }

                NavigationLink {
                    ProjectKitCameraSelectionView(store: store)
                        .environmentObject(authService)
                } label: {
                    Label("Add Camera", systemImage: "plus")
                }
            }

            Section("Lenses") {
                let selected = store.selectedLenses()
                ForEach(selected) { lens in
                    VStack(alignment: .leading) {
                        Text("\(lens.brand) \(lens.series)")
                        Text(lensLabel(for: lens))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(
                            "Lens", systemImage: "trash",
                            role: .destructive
                        ) {
                            store.removeLens(id: lens.id, projectId: authService.projectId)
                        }
                        .tint(.red)
                        if let pack = store.lensPack(for: lens) {
                            Button(
                                "Lens Pack", systemImage: "trash",
                                role: .destructive
                            ) {
                                store.removeLensPack(id: pack.id, projectId: authService.projectId)
                            }
                            .tint(.red)
                        }
                    }
                }
                .onDelete { indexSet in
                    removeLenses(at: indexSet, from: selected)
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
        if lens.isZoom, let min = lens.focalLengthMinMm, let max = lens.focalLengthMaxMm {
            return "\(Int(min))–\(Int(max))mm T\(lens.maxTStop)"
        }
        if let focal = lens.focalLengthMm ?? lens.focalLengthMinMm {
            return "\(Int(focal))mm T\(lens.maxTStop)"
        }
        return "T\(lens.maxTStop)"
    }

    private func cameraSensorLabel(_ camera: DBCamera) -> String {
        if let width = camera.sensorWidthMm, let height = camera.sensorHeightMm {
            return "Sensor \(String(format: "%.2f", width)) × \(String(format: "%.2f", height)) mm"
        }
        if let sensorType = camera.sensorType, !sensorType.isEmpty {
            return "Sensor \(sensorType)"
        }
        return "Sensor size unavailable"
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
