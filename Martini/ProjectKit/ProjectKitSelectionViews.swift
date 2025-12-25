import SwiftUI

struct ProjectKitCameraSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService
    @ObservedObject var store: ProjectKitStore
    @State private var searchText = ""
    @State private var selectedIds: Set<String> = []
    @State private var showingProjectAlert = false

    private var availableCameras: [DBCamera] {
        let filtered = store.availableCameras.filter { camera in
            !store.selectedCameraIds.contains(camera.id)
        }
        if searchText.isEmpty {
            return filtered.sorted { "\($0.brand) \($0.model)" < "\($1.brand) \($1.model)" }
        }
        let query = searchText.lowercased()
        return filtered.filter {
            "\($0.brand) \($0.model)".lowercased().contains(query)
        }.sorted { "\($0.brand) \($0.model)" < "\($1.brand) \($1.model)" }
    }

    var body: some View {
        List {
            ForEach(availableCameras) { camera in
                Button {
                    toggleSelection(id: camera.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(camera.brand) \(camera.model)")
                            Text("Sensor \(camera.sensorWidthMm, specifier: "%.2f") × \(camera.sensorHeightMm, specifier: "%.2f") mm")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedIds.contains(camera.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle("Add Camera")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .onAppear {
            store.load(for: authService.projectId)
        }
        .onChange(of: authService.projectId) { _ in
            store.load(for: authService.projectId)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !selectedIds.isEmpty {
                    Button("Add") {
                        guard authService.projectId != nil else {
                            showingProjectAlert = true
                            return
                        }
                        store.addCameras(ids: Array(selectedIds), projectId: authService.projectId)
                        dismiss()
                    }
                }
            }
        }
        .alert("Project unavailable", isPresented: $showingProjectAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please log into a project before adding cameras.")
        }
    }

    private func toggleSelection(id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }
}

struct ProjectKitLensSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService
    @ObservedObject var store: ProjectKitStore
    @State private var searchText = ""
    @State private var selectedIds: Set<String> = []
    @State private var showingProjectAlert = false

    private var availableLenses: [DBLens] {
        let filtered = store.availableLenses.filter { lens in
            !store.selectedLensIds.contains(lens.id)
        }
        if searchText.isEmpty {
            return filtered.sorted { "\($0.brand) \($0.series)" < "\($1.brand) \($1.series)" }
        }
        let query = searchText.lowercased()
        return filtered.filter {
            "\($0.brand) \($0.series)".lowercased().contains(query)
        }.sorted { "\($0.brand) \($0.series)" < "\($1.brand) \($1.series)" }
    }

    var body: some View {
        List {
            ForEach(availableLenses) { lens in
                Button {
                    toggleSelection(id: lens.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(lens.brand) \(lens.series)")
                            Text(lensLabel(for: lens))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedIds.contains(lens.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle("Add Lens")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .onAppear {
            store.load(for: authService.projectId)
        }
        .onChange(of: authService.projectId) { _ in
            store.load(for: authService.projectId)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !selectedIds.isEmpty {
                    Button("Add") {
                        guard authService.projectId != nil else {
                            showingProjectAlert = true
                            return
                        }
                        store.addLenses(ids: Array(selectedIds), projectId: authService.projectId)
                        dismiss()
                    }
                }
            }
        }
        .alert("Project unavailable", isPresented: $showingProjectAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please log into a project before adding lenses.")
        }
    }

    private func toggleSelection(id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func lensLabel(for lens: DBLens) -> String {
        if lens.isZoom {
            return "\(Int(lens.focalLengthMinMm))–\(Int(lens.focalLengthMaxMm))mm T\(lens.tStop)"
        }
        return "\(Int(lens.focalLengthMinMm))mm T\(lens.tStop)"
    }
}
