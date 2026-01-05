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
                            Text(cameraSensorLabel(camera))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedIds.contains(camera.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Select Camera")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .onAppear {
            store.load(for: authService.projectId)
        }
        .onChange(of: authService.projectId) { _ in
            store.load(for: authService.projectId)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Select Camera")
                        .font(.headline)
                    Text(selectedCameraCountText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !selectedIds.isEmpty {
                    Button {
                        guard authService.projectId != nil else {
                            showingProjectAlert = true
                            return
                        }
                        store.addCameras(ids: Array(selectedIds), projectId: authService.projectId)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .tint(.primary)
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

    private var selectedCameraCountText: String {
        let count = selectedIds.count
        let label = count == 1 ? "camera" : "cameras"
        return "\(count) \(label) selected"
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
}

struct ProjectKitLensSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService
    @ObservedObject var store: ProjectKitStore
    @State private var searchText = ""
    @State private var selectedIds: Set<String> = []
    @State private var showingProjectAlert = false
    @State private var shouldDismissToSettings = false

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

    private var availableLensPacks: [ProjectKitStore.LensPackGroup] {
        let packs = store.availableLensPacks()
        guard !searchText.isEmpty else { return packs }
        let query = searchText.lowercased()
        return packs.filter { $0.displayName.lowercased().contains(query) }
    }

    var body: some View {
        List {
            if !availableLensPacks.isEmpty {
                Section("Lens Packs") {
                    ForEach(availableLensPacks) { pack in
                        NavigationLink {
                            LensPackDetailView(
                                pack: pack,
                                selectedIds: $selectedIds,
                                shouldDismissToSettings: $shouldDismissToSettings,
                                onAdd: { addSelectedLenses(dismissAfter: false) }
                            )
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pack.displayName)
                                    Text("\(pack.lenses.count) lenses")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }

            Section("All Lenses") {
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
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            }
        }
        .navigationTitle("Select Lenses")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .onAppear {
            store.load(for: authService.projectId)
        }
        .onChange(of: authService.projectId) { _ in
            store.load(for: authService.projectId)
        }
        .onChange(of: shouldDismissToSettings) { shouldDismiss in
            guard shouldDismiss else { return }
            dismiss()
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Select Lenses")
                        .font(.headline)
                    Text(selectedLensCountText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !selectedIds.isEmpty {
                    Button {
                        addSelectedLenses()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .tint(.primary)
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

    private func addSelectedLenses() {
        addSelectedLenses(dismissAfter: true)
    }

    private func addSelectedLenses(dismissAfter: Bool) {
        guard authService.projectId != nil else {
            showingProjectAlert = true
            return
        }
        store.addLenses(ids: Array(selectedIds), projectId: authService.projectId)
        if dismissAfter {
            dismiss()
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

    private var selectedLensCountText: String {
        let count = selectedIds.count
        let label = count == 1 ? "lens" : "lenses"
        return "\(count) \(label) selected"
    }

}

private struct LensPackDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let pack: ProjectKitStore.LensPackGroup
    @Binding var selectedIds: Set<String>
    @Binding var shouldDismissToSettings: Bool
    let onAdd: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(pack.lenses) { lens in
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
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(pack.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !pack.lenses.isEmpty {
                    Button {
                        selectedIds.formUnion(pack.lenses.map(\.id))
                    } label: {
                        Image(systemName: "checkmark.rectangle.stack")
                    }
                    .tint(.primary)
                }
                if !selectedIds.isEmpty {
                    Button {
                        onAdd()
                        shouldDismissToSettings = true
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .tint(.primary)
                }
            }
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
        if lens.isZoom, let min = lens.focalLengthMinMm, let max = lens.focalLengthMaxMm {
            return "\(Int(min))–\(Int(max))mm T\(lens.maxTStop)"
        }
        if let focal = lens.focalLengthMm ?? lens.focalLengthMinMm {
            return "\(Int(focal))mm T\(lens.maxTStop)"
        }
        return "T\(lens.maxTStop)"
    }
}
