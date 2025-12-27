import SwiftUI

struct FOVCalibrationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var scoutViewModel: ScoutCameraViewModel
    @StateObject private var viewModel: FOVCalibrationViewModel
    @ObservedObject private var store: FOVCalibrationStore

    private let sliderRange: ClosedRange<Double> = 0.95...1.05

    init(scoutViewModel: ScoutCameraViewModel) {
        self.scoutViewModel = scoutViewModel
        let store = scoutViewModel.calibrationStore
        _viewModel = StateObject(wrappedValue: FOVCalibrationViewModel(store: store))
        _store = ObservedObject(wrappedValue: store)
    }

    var body: some View {
        NavigationStack {
            List {
                if let match = scoutViewModel.matchResult {
                    Section {
                        HStack {
                            Text("Matched")
                            Spacer()
                            Text("\(FOVCalibrationModule.displayName(for: match.cameraRole)) @ \(String(format: "%.2fx", match.zoomFactor))")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }

                if viewModel.modules.isEmpty {
                    Section {
                        Text("No camera modules available for calibration.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(viewModel.modules) { module in
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(module.displayName)
                                        .font(.headline)
                                    Spacer()
                                    Button("Reset") {
                                        viewModel.reset(role: module.role)
                                    }
                                    .font(.caption.weight(.semibold))
                                }

                                Slider(value: binding(for: module.role), in: sliderRange, step: 0.01)

                                Text("Framing: Wider ↔ Tighter")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text("Multiplier: \(String(format: "%.2fx", store.multiplier(for: module.role)))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("FOV Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset All") {
                        viewModel.resetAll()
                    }
                    .disabled(viewModel.modules.isEmpty)
                }
            }
        }
        .onChange(of: store.multipliers) { _ in
            Task { await scoutViewModel.updateCaptureConfiguration() }
        }
    }

    private func binding(for role: String) -> Binding<Double> {
        Binding(
            get: { store.multiplier(for: role) },
            set: { value in
                store.setMultiplier(value, for: role)
            }
        )
    }
}
